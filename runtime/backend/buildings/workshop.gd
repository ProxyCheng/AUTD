class_name Workshop
extends Building

# 工人驱动的机器基类(作坊)。机器 = 一张(或多张)配方 + 一名工人注入工作量。
#
# 配方体系:本基类持有 recipes(Array[RecipeData])作为配方列表,按数组顺序决定执行
# 优先级(越靠前越优先)。每次生产从列表里按优先级挑出"当前可执行"的配方
# (见 _selected_recipe:输入齐备且输出仓未满),消费其 inputs、兑现其 output。
# GUI 通过 move_recipe(from, to) 调整顺序即可改变执行优先级,无需改代码。
#
# 配方形态(与 RecipeData 注释一致):
#   * 无输入有输出:伐木场/石矿(采天然资源入输出仓);
#   * 有输入有输出:车间(消耗原木+石头 → 产箭);
#   * 有输入无输出:弩炮(消耗箭矢,产出的是一次发射这一即时效果,不落输出仓)。
#
# 子类约定:在 _ready() 里调用 super._ready() 之前填充 recipes。需要额外输入仓的
# 子类(如车间建原木/石头输入仓)可覆写 _setup_bags 并在开头 super;或用 _make_bag
# 自建。弩炮这类即时效果机器不纳配方(recipes 为空),完全走自有 _tick_machine/_apply_workload。
#
# 生命周期:机器在 _needs_worker() 为真且无人值守时,向 LaborManager 注册一个
# ManBuildingTask(required_count=1, priority=manning_priority()):派一名工人沿行为树走到
# 岗位点(work_entry_position),每 tick 由 ProvideWorkloadTask 调 work(in_workload) 注入
# 驱动量;注入同时维护"有人值守"窗口(_manned_timer)。直到 is_work_done() 判定本轮一次
# 生产完成,工人离岗归还调度池,机器随后按 _needs_worker() 再次补位。
#
# 子类钩子(按需覆盖):_setup_bags/_needs_worker/is_work_done/_reset_shift/_tick_machine/
# work_entry_position/manning_priority。勿覆盖 tick()/work() —— 通用生命周期已在基类实现。

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

# 配方列表(顺序 = 执行优先级,越靠前越优先)。子类在 _ready 填充。
var recipes: Array[RecipeData] = []

# 当前被选中的配方(只读,见 _selected_recipe;null = 当前无可行配方)
var active_recipe: RecipeData = null:
	get:
		return active_recipe
	set(in_recipe):
		if in_recipe == active_recipe:
			return
		active_recipe = in_recipe
		active_recipe_changed.emit()
signal active_recipe_changed()

@export var workload_per_unit: float = 2.0
# 输出仓/输入仓物理上限(满则停止生产、工人离岗等物流搬空/补足)
@export var output_capacity: int = 30

# 输出仓(纯供给方:有货即外供),按产出物类型各一只:同一车间可声明多种产出(如箭/炮弹),
# 每种产出建一只仓,产出时按配方 output 路由到对应仓(见 _output_bag_for)。
var output_bags: Dictionary = {}  # { item_type: Bag }
# 展示镜像仓:取第一只输出仓(单产出车间的唯一输出仓);无产出的瞬时效果机器(弩炮)为 null。
var output_bag: Bag = null

# 本机创建的全部仓(输出仓 + 输入仓),退出时统一注销
var _bags: Array[Bag] = []

# 当前累计工作量(本件产出的进度;相对 active_recipe.workload_per_unit)
var work_accum: float = 0

# —— 对外可观察存量镜像 ——
# 镜像目标:生产类 = 输出仓;消耗类 = 弹药输入仓。由 _bind_mirror 指定。

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

# —— 配方列表操作(GUI 拖动排序入口)——

# 把配方从 in_from 移到 in_to(索引),其余配方顺序保持不变;越靠前越优先。
func move_recipe(in_from: int, in_to: int):
	if in_from < 0 or in_from >= recipes.size():
		return
	if in_to < 0 or in_to >= recipes.size():
		return
	if in_from == in_to:
		return
	var recipe: RecipeData = recipes[in_from]
	recipes.remove_at(in_from)
	recipes.insert(in_to, recipe)
	recipe_order_changed.emit()

signal recipe_order_changed()

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
	return _selected_recipe() != null

func _is_manned() -> bool:
	return _manned_timer > 0

# 岗位点:机器所在格子的固定角(相对自身坐标 WORK_ENTRY_OFFSET),贴机器且不重叠。
func work_entry_position() -> Vector2:
	return Vector2(axis) + WORK_ENTRY_OFFSET

# 该机器顶岗任务的调度优先级(子类可覆盖;攻击建筑如 Crossbow 设为更高档,
# 保证驱动机器产出的任务不被普通物流挤占)。默认=生产 10。
func manning_priority() -> int:
	return 10

# —— 配方查询:当前应执行的配方 ——

# 从 recipes 按优先级挑出第一个"当前可执行"的配方。
# 可执行 = 输出仓未满(若无输出则视为真)且输入齐备。
# 返回前同步 active_recipe(有变化则触发 active_recipe_changed),供 frontend 高亮当前执行配方。
func _selected_recipe() -> RecipeData:
	var chosen: RecipeData = null
	for recipe: RecipeData in recipes:
		if _is_recipe_executable(recipe):
			chosen = recipe
			break
	active_recipe = chosen
	return chosen

# 单张配方的可执行性:输出仓未满(无输出则视为真)且输入齐备。
func _is_recipe_executable(in_recipe: RecipeData) -> bool:
	var bag: Bag = _output_bag_for(in_recipe.output)
	if bag and bag.is_full():
		return false
	return _has_inputs_for(in_recipe)

# —— 子类钩子:值岗生命周期 / 机器推进 ——

func _reset_shift():
	pass

# 默认配方兑现:工作量线性累计,攒满一件即产出入仓,剩余部分留作下一件进度。
func _apply_workload(in_workload: float):
	var recipe := _selected_recipe()
	if recipe == null:
		return
	if recipe.output != "" and output_bag and output_bag.is_full():
		return
	work_accum += in_workload
	while work_accum >= recipe.workload_per_unit:
		if not _produce_unit():
			break
		work_accum -= recipe.workload_per_unit
	progress = clampf(work_accum / recipe.workload_per_unit, 0.0, 1.0)

# 机器帧推进:维护建筑可观察 state(供 frontend 播/静止)。仅"有人值守且在产出"时
# 置 "working",否则 "idle" —— 前端动画只在真正生产时播放。产出进度归零语义留给子类。
func _tick_machine(_in_delta: float):
	var recipe := _selected_recipe()
	var bag: Bag = _output_bag_for(recipe.output) if recipe else null
	if recipe == null or (bag and bag.is_full()) or not _is_manned():
		if state != "idle":
			state = "idle"
	else:
		if state != "working":
			state = "working"

# —— 配方产出物(供 GUI/档位显示;派生自当前配方)——

# 当前优先选中配方的输出物类型;无配方或瞬时效果机器返回 ""。
func _produces() -> String:
	var recipe := _selected_recipe()
	return recipe.output if recipe else ""

# 收集全部配方声明的产出类型(去重,保持出现顺序;output 为空的瞬时效果配方跳过)。
# 供 _setup_bags 决定建设哪些输出仓 —— 输出仓类型由配方"声明"决定,而非"当前是否可执行"
# (否则输入仓未建齐时会因输入不足误判为空,连输出仓都建不出来)。
func _collect_output_types() -> Array[String]:
	var types: Array[String] = []
	for recipe: RecipeData in recipes:
		if recipe.output == "" or recipe.output in types:
			continue
		types.append(recipe.output)
	return types

# —— 输入校验/扣减(按配方 inputs 泛化)——

# 校验某配方全部输入是否齐备(各输入 bag 数量足够)。
func _has_inputs_for(in_recipe: RecipeData) -> bool:
	if in_recipe.inputs.is_empty():
		return true
	for input: RecipeInputData in in_recipe.inputs:
		var bag: Bag = _find_input_bag(input.item_type)
		if bag == null or bag.count < input.count:
			return false
	return true

# 扣减某配方全部输入;任一不足则整体失败(返回 false,不做部分扣减)。
func _consume_inputs_for(in_recipe: RecipeData) -> bool:
	if in_recipe.inputs.is_empty():
		return true
	# 先全量校验再扣,避免半扣
	for input: RecipeInputData in in_recipe.inputs:
		var bag: Bag = _find_input_bag(input.item_type)
		if bag == null or bag.count < input.count:
			return false
	for input: RecipeInputData in in_recipe.inputs:
		_find_input_bag(input.item_type).remove_count(input.count)
	return true

# 按原料类型查找本机输入仓;不存在实例时返回 null(调用方决定是否自建)。
func _find_input_bag(in_item_type: String) -> Bag:
	for bag: Bag in _bags:
		if bag.item_type == in_item_type:
			return bag
	return null

# 按产出物类型取本机输出仓;output 为 ""(瞬时效果配方)或无该类型仓时返回 null。
func _output_bag_for(in_item_type: String) -> Bag:
	if in_item_type == "":
		return null
	var bag: Bag = output_bags.get(in_item_type)
	return bag

# 公开只读:某物料在当前建筑全部仓中的存量(输入仓 + 输出仓按类型匹配)。
# 供 frontend 配方行显示库存;无该物料仓时返回 0。只读,不改状态。
func get_stock(in_item_type: String) -> int:
	var total: int = 0
	for bag: Bag in _bags:
		if bag.item_type == in_item_type:
			total += bag.count
	return total

# 公开只读:某物料在当前建筑对应仓的容量上限(供 frontend 竖向条显示库存占比分母)。
# 无该物料仓时返回 0。只读。
func get_capacity(in_item_type: String) -> int:
	for bag: Bag in _bags:
		if bag.item_type == in_item_type:
			return bag.max_count
	return 0

# —— 仓装配 ——

# 由配方综合推断并建仓:每种"所需物品类型"只建一只仓。
# 规则(Bag 按类型一只):把全部配方声明收集起来,凡某类型出现在任一配方的 input 中,
# 就建一只该类型的纯需求方输入仓;凡某类型是某配方的 output,就建一只该类型的纯供给方
# 输出仓。子类只需声明 recipes,无需手写建 input_bag/log_bag/stone_bag。
# 弩炮这类即时效果机器(recipes 为空)完全覆写本方法自建弹药仓。
func _setup_bags():
	# 输入仓:收集全部配方所需的输入类型(去重),每种建一只纯需求方
	for item_type: String in _collect_input_types():
		_make_bag("InputBag_%s" % item_type, item_type, output_capacity, true)
	# 输出仓:收集全部配方声明的产出类型(去重),每种建一只纯供给方
	for item_type: String in _collect_output_types():
		output_bags[item_type] = _make_bag("OutputBag_%s" % item_type, item_type, output_capacity, false)
	# 展示镜像取第一只输出仓(单产出车间的唯一输出仓);弩炮等无产出机器保持 null
	for bag: Bag in output_bags.values():
		output_bag = bag
		_bind_mirror(output_bag)
		break

# 收集全部配方所需的输入类型(去重,保持出现顺序)。
func _collect_input_types() -> Array[String]:
	var types: Array[String] = []
	for recipe: RecipeData in recipes:
		for input: RecipeInputData in recipe.inputs:
			if input.item_type in types:
				continue
			types.append(input.item_type)
	return types

# 多 Bag 建筑容量条显示占用最满的那个(默认遍历全部仓;单仓建筑退化为该仓占比)。
func occupancy_fill() -> float:
	var best: float = 0.0
	for bag: Bag in _bags:
		if bag == null or bag.max_count <= 0:
			continue
		best = maxf(best, clampf(float(bag.count) / float(bag.max_count), 0.0, 1.0))
	return best

# —— 内部 ——

# 实际产出一件:先扣输入(可过),再向输出仓塞一件(自带上限截断)。
func _produce_unit() -> bool:
	var recipe := _selected_recipe()
	if recipe == null:
		return false
	var bag: Bag = _output_bag_for(recipe.output)
	if bag and bag.is_full():
		return false
	if not _consume_inputs_for(recipe):
		return false
	if bag:
		# 按配方 output_count 一次入仓多件(默认 1);"2x+3y->2z" 等比例方与实际产出一致
		bag.add_count(recipe.output_count)
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

# 展示仓 = 已注册为展示镜像的仓(Workshop 为 output_bag;Crossbow 经 _bind_mirror 为 input_bag)。
func get_display_bag() -> Bag:
	return _mirror_bag

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
