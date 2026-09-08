class_name Workshop
extends Building

# 工人驱动的机器基类(作坊)。机器 = 一张配方 + 一名工人注入工作量;配方未必同时有
# 输入与输出,可能只有其一甚至两者皆无:
#   * 无输入有输出:伐木场/石矿(采天然资源入输出仓);
#   * 有输入有输出:车间(消耗原木+石头 → 产箭);
#   * 有输入无输出:弩炮(消耗箭矢弹药,产出的是一次发射这一即时效果,不落输出仓)。
# 本基类负责整条通用生命周期:无人值守时自动补员 → 工人沿行为树走到岗位点 → 每 tick
# 注入工作量(work) → 工作量按配方兑现 → 一次生产完成(is_work_done)后放工人离岗。
#
# 生命周期:机器在 _needs_worker() 为真且无人值守时,向 LaborManager 注册一个
# ManBuildingTask(required_count=1, priority=manning_priority()):派一名工人沿行为树走到
# 岗位点(work_entry_position),每 tick 由 ProvideWorkloadTask 调 work(in_workload) 注入
# 驱动量;注入同时维护"有人值守"窗口(_manned_timer)。直到 is_work_done() 判定本轮一次
# 生产完成,工人离岗归还调度池,机器随后按 _needs_worker() 再次补位。无人值守期间机器
# 表现(是否停摆)由子类决定。
#
# 子类钩子(按需覆盖):
#   _produces()             输出物类型;返回 "" = 无输出仓(默认 "",弩炮等即时效果机器)
#   _setup_bags()           装配仓:默认按 _produces() 建一个纯供给输出仓;需要输入仓的
#                           子类(车间/弩炮)覆写并在开头调用 super._setup_bags()
#   _needs_worker() -> bool 是否需要顶岗工人(默认:输出仓未满且输入齐备)
#   is_work_done()  -> bool  本轮一次生产是否已完成(默认 = 输出仓满或输入耗尽)
#   _apply_workload(amount)  把注入的驱动量换算成自身进度/产出(默认:攒满一件产出入仓)
#   _tick_machine(in_delta)  机器每帧推进(基类 tick 先做值守维护再调它;默认维护 idle/working)
#   _reset_shift()           新一轮值岗(工人更替后首次注入)开始时的复位(默认空)
#   _has_inputs() / _consume_inputs()  配方的输入校验/实际扣减(默认恒真 = 无输入)
#   work_entry_position()    岗位点(默认 = 自身格子 + WORK_ENTRY_OFFSET)
#   manning_priority()       顶岗任务调度优先级(默认 10;攻击建筑如 Crossbow 覆写更高)
# 不要覆盖 tick()/work() —— 通用生命周期已在基类实现,需要机器帧推进请实现 _tick_machine。

# 有人值守判定窗口:超过该时长无 work() 注入即视为无人,机器可据此停摆
const MANNED_TIMEOUT: float = 0.2
# 岗位点相对机器格子的固定偏移(方向/大小按模型微调;不同机器可在 work_entry_position 覆写)
const WORK_ENTRY_OFFSET: Vector2 = Vector2(0.4, 0.4)

var required_workers: int = 1
var workers: Array = []
var manning_task: ManBuildingTask = null
var _worker_requested: bool = false
var _manned_timer: float = 0  # >0 表示有人值守(近期有工人注入 work())

# —— 配方 / 生产参数 ——

# 产出一件所需的累计工作量(秒,工人效率=1 时)
@export var workload_per_unit: float = 2.0
# 输出仓/输入仓物理上限(满则停止生产、工人离岗等物流搬空/补足)
@export var output_capacity: int = 30

# 输出仓(纯供给方:有货即外供)。仅 _produces() 非空时由基类 _setup_bags 创建。
var output_bag: Bag = null

# 本机创建的全部仓(输出仓 + 子类输入仓),退出时统一注销
var _bags: Array[Bag] = []

# 当前累计工作量(本件产出的进度)
var work_accum: float = 0

# —— 对外可观察存量镜像 ——
# 镜像目标:生产类 = 输出仓;弩炮等消耗类 = 弹药输入仓。由 _bind_mirror 指定。

var stored_count: int = 0:
	get:
		return stored_count
	set(in_count):
		if in_count == stored_count:
			return
		stored_count = in_count
		stored_count_changed.emit()
signal stored_count_changed()

var _mirror_bag: Bag = null  # stored_count/capacity 的镜像源

# 展示容量(只读,供 frontend 归一化显示;派生自镜像仓 max_count,不存两份)
var capacity: int:
	get:
		return _mirror_bag.max_count if _mirror_bag else 0

func _ready():
	_setup_bags()
	_maintain_manning()

func _exit_tree():
	_unregister_bags()
	_cancel_worker_request()

# 机器主循环:先做值守/补员维护,再交子类推进机器自身逻辑。
func tick(in_delta: float):
	_manned_timer = maxf(_manned_timer - in_delta, 0)
	_maintain_manning()
	_tick_machine(in_delta)

# —— 工人驱动入口(由 ProvideWorkloadTask 每 tick 调用,勿由子类覆盖)——
func work(in_workload: float):
	var was_unmanned := not _is_manned()
	_manned_timer = MANNED_TIMEOUT
	if was_unmanned:
		_reset_shift()
	_apply_workload(in_workload)

func is_work_done() -> bool:
	return not _needs_worker()

func _needs_worker() -> bool:
	if not output_bag or output_bag.is_full():
		return false
	return _has_inputs()

func _is_manned() -> bool:
	return _manned_timer > 0

# 岗位点:机器所在格子的固定角(相对自身坐标 WORK_ENTRY_OFFSET),贴机器且不重叠。
func work_entry_position() -> Vector2:
	return Vector2(axis) + WORK_ENTRY_OFFSET

# 该机器顶岗任务的调度优先级(子类可覆盖;攻击建筑如 Crossbow 设为更高档,
# 保证驱动机器产出的任务不被普通物流挤占)。默认=生产 10。
func manning_priority() -> int:
	return 10

# —— 子类钩子:值岗生命周期 / 机器推进 ——

func _reset_shift():
	pass

# 默认配方兑现:工作量线性累计,攒满 workload_per_unit 即产出一件入输出仓,
# 剩余部分留作下一件进度(连续产出,直到输出仓满或输入耗尽)。
func _apply_workload(in_workload: float):
	if not output_bag or output_bag.is_full():
		return
	work_accum += in_workload
	while work_accum >= workload_per_unit:
		if not _produce_unit():
			break
		work_accum -= workload_per_unit
	progress = clampf(work_accum / workload_per_unit, 0.0, 1.0)

# 机器帧推进:维护建筑可观察 state(供 frontend 播/静止)。产出进度归零语义留给子类。
func _tick_machine(_in_delta: float):
	if not _is_manned() or (output_bag and output_bag.is_full()) or not _has_inputs():
		if state != "idle":
			state = "idle"
	else:
		if state != "working":
			state = "working"

# —— 配方声明(默认:无输出、无输入;子类覆写) ——

# 输出物类型;返回 "" = 无输出仓(即时效果机器,如弩炮)。
func _produces() -> String:
	return ""

# 输入是否齐备(是否满足本件产出的输入;树/石矿无输入恒真;车间需原木+石头)
func _has_inputs() -> bool:
	return true

# 实际消耗一件所需的输入(车间扣原木+石头;树/石矿为空)
func _consume_inputs() -> bool:
	return true

# —— 仓装配 ——

# 默认配方仓:声明了产出物(_produces() 非空)才建一只纯供给输出仓并作展示镜像。
# 需要输入仓的子类(车间建原木/石头输入仓,弩炮建弹药仓)覆写本方法并在开头调用 super。
func _setup_bags():
	var produced: String = _produces()
	if produced == "":
		return
	output_bag = _make_bag("OutputBag", produced, output_capacity, false)
	_bind_mirror(output_bag)

# —— 内部 ——

# 实际产出一件:先扣输入(可过),再向输出仓塞一件(自带上限截断)。
func _produce_unit() -> bool:
	if not output_bag or output_bag.is_full():
		return false
	if not _consume_inputs():
		return false
	output_bag.add_count(1)
	return true

# 建一只参与物流的仓并注册。is_demand = true 为纯需求方(低于上限即求补到满,永不外供,
# 如车间输入仓/弩炮弹药仓);false 为纯供给方(有货即外供,如输出仓)。
func _make_bag(in_name: String, in_item_type: String, in_capacity: int,
		in_is_demand: bool, in_transport_priority: int = 0) -> Bag:
	var bag := Bag.new()
	bag.name = in_name
	bag.item_type = in_item_type
	bag.max_count = in_capacity
	bag.access_position = Vector2(axis)
	bag.transport_priority = in_transport_priority
	if in_is_demand:
		bag.preferred_min_count = in_capacity
		bag.preferred_max_count = in_capacity
	else:
		bag.preferred_min_count = 0
		bag.preferred_max_count = 0
	add_child(bag)
	bag.owner = owner
	_bags.append(bag)
	_register_bag(bag)
	return bag

# 指定 stored_count/capacity 的镜像源仓(先断开旧仓连接再连,防重绑重复回调)。
func _bind_mirror(in_bag: Bag):
	if _mirror_bag and _mirror_bag.count_changed.is_connected(_sync_stored_count):
		_mirror_bag.count_changed.disconnect(_sync_stored_count)
	_mirror_bag = in_bag
	if _mirror_bag and not _mirror_bag.count_changed.is_connected(_sync_stored_count):
		_mirror_bag.count_changed.connect(_sync_stored_count)
	_sync_stored_count()

# 镜像仓 count 变化 → 同步镜像属性,经 setter 触发 stored_count_changed
func _sync_stored_count():
	stored_count = _mirror_bag.count if _mirror_bag else 0

func _register_bag(in_bag: Bag):
	var logistics: Logistics = _get_logistics()
	if logistics:
		logistics.register_bag(in_bag)

func _unregister_bags():
	var logistics: Logistics = _get_logistics()
	if not logistics:
		return
	for bag: Bag in _bags:
		logistics.unregister_bag(bag.id)
	_bags.clear()

# —— 补员调度 ——

func _get_manager() -> LaborManager:
	if not Level.current:
		return null
	return Level.current.labor_manager

func _get_logistics() -> Logistics:
	if not Level.current:
		return null
	return Level.current.logistics

# 每帧按需维护:无人且机器需要工人、且没有在途请求时,注册一个顶岗任务。
# 任务在 is_work_done()(射出一发/产出一件)后完成,或工人流失被取消;
# 任务节点被释放后自动补位(LaborManager 派最近空闲工人,通常仍是刚离岗、守在岗位旁的那位)。
func _maintain_manning():
	if not is_inside_tree():
		return
	var manager := _get_manager()
	if not manager:
		return
	if _worker_requested:
		if manning_task and is_instance_valid(manning_task):
			return
		_worker_requested = false
	if not _is_manned() and _needs_worker():
		_worker_requested = true
		manning_task = ManBuildingTask.new(self, work_entry_position(), 1, manning_priority())
		manager.register_task(manning_task)

func _cancel_worker_request():
	_worker_requested = false
	var manager := _get_manager()
	if is_instance_valid(manager) and manning_task and is_instance_valid(manning_task):
		manager.cancel_task(manning_task)
	manning_task = null
