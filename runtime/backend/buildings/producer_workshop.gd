class_name ProducerWorkshop
extends Workshop

# 生产型机器(如伐木场、石矿):工人注入 workload 累积,攒满 WORKLOAD_PER_UNIT
# 即向 output_bag 产出一件本建筑专产物品。生产是连续的——只要输出仓有空位
# (且输入齐备,见 _has_inputs)就保持值守,直到输出仓满(或输入耗尽)才放工人离岗。
# 产出物经 Logistics 提供的纯供给方语义(有货即外供)搬运给下游需求方。
#
# 与 Crossbow 的区别:弩炮"一工班射一发"、无产出仓;本类把工作量线性兑换成物品,
# 是"资源开采/加工"建筑。子类通过覆写钩子描述自身,见文件尾部的钩子说明。
#
# 子类钩子:
#   _produces()          本建筑输出物类型(默认 "log";石矿/车间覆写)
#   _has_inputs()        是否满足本件产出的输入(树/石矿无输入恒真;车间需原木+石头)
#   _consume_inputs()    实际消耗一件所需的输入(车间扣原木+石头;树/石矿为空)
#   _setup_bags()        额外创建并注册输入包(车间建原木/石头输入仓;默认只建输出仓)
# 不要覆盖 tick()/work()/is_work_done()/_needs_worker() —— 通用生命周期已在基类实现。

# 产出一件所需的累计工作量(秒,工人效率=1 时)
@export var workload_per_unit: float = 2.0
# 输出仓物理上限(满则停止生产、工人离岗等物流搬空)
@export var output_capacity: int = 30

# 输出仓(纯供给方:有货即外供)。挂在本建筑下,由 Logistics 统一调度搬运。
var output_bag: Bag = null

# 当前累计工作量(本件产出的进度)
var work_accum: float = 0

# 输出存量镜像(output_bag.count 的对外可观察副本)。setter 只由内部 _sync_output 驱动。
var stored_count: int = 0:
	get:
		return stored_count
	set(in_count):
		if in_count == stored_count:
			return
		stored_count = in_count
		stored_count_changed.emit()
signal stored_count_changed()

# 输出仓容量(只读,供 frontend 归一化显示;派生自 output_capacity,不存两份)
var capacity: int:
	get:
		return output_capacity

func _ready():
	output_bag = Bag.new()
	output_bag.name = "OutputBag"
	output_bag.item_type = _produces()
	output_bag.max_count = output_capacity
	# 纯供给方:低于上限不请求补货(preferred_min=0),超出 0 即外供(有货即外运)
	output_bag.preferred_min_count = 0
	output_bag.preferred_max_count = 0
	output_bag.access_position = Vector2(axis)
	add_child(output_bag)
	output_bag.owner = owner
	output_bag.count_changed.connect(_sync_output)
	_register_bag()
	_setup_bags()
	_sync_output()
	_maintain_manning()

func _exit_tree():
	# 连同子类创建的输入包一并注销(子类自建的包由子类 _exit_tree 覆写处理)
	_unregister_bag()
	super._exit_tree()

# —— 生产语义 ——

# 工人值守条件:输出仓未满(空位可继续产出)。车间额外要求输入齐备(见 _has_inputs)。
func _needs_worker() -> bool:
	if output_bag and output_bag.is_full():
		return false
	return _has_inputs()

# 本轮产出完成:输出仓满(或输入耗尽)即视为产完,放工人离岗,由基建派新班补位。
func is_work_done() -> bool:
	return not _needs_worker()

# 一次"搬运周期"在新工人注入后真正开始;采掘类建筑产出连续,无需额外复位。
# (基类在工人更替时于首次注入调用本钩子,默认空即可。)

# 工作量累计 → 产出:攒满一件即产出,剩余部分留作下一件进度。
func _apply_workload(in_workload: float):
	if not output_bag or output_bag.is_full():
		return
	work_accum += in_workload
	while work_accum >= workload_per_unit:
		if not _produce_unit():
			break
		work_accum -= workload_per_unit
	progress = clampf(work_accum / workload_per_unit, 0.0, 1.0)

# 机器帧推进:维护建筑可观察 state(供 frontend 播/静止),产出进度归零语义留给子类。
func _tick_machine(_in_delta: float):
	if not _is_manned() or (output_bag and output_bag.is_full()) or not _has_inputs():
		if state != "idle":
			state = "idle"
	else:
		if state != "working":
			state = "working"

# —— 子类钩子(默认:采伐原木、无输入) ——

func _produces() -> String:
	return "log"

func _has_inputs() -> bool:
	return true

func _consume_inputs() -> bool:
	return true

func _setup_bags():
	pass

# —— 内部 ——

# 实际产出一件:先扣输入(可过),再向输出仓塞一件(自带上限截断)。
func _produce_unit() -> bool:
	if not output_bag or output_bag.is_full():
		return false
	if not _consume_inputs():
		return false
	output_bag.add_count(1)
	return true

# output_bag.count 变化 → 同步镜像属性,经 setter 触发 stored_count_changed
func _sync_output():
	stored_count = output_bag.count if output_bag else 0

func _register_bag():
	var logistics: Logistics = _get_logistics()
	if logistics:
		logistics.register_bag(output_bag)

func _unregister_bag():
	var logistics: Logistics = _get_logistics()
	if logistics and output_bag:
		logistics.unregister_bag(output_bag.id)

func _get_logistics() -> Logistics:
	if not Level.current:
		return null
	return Level.current.logistics
