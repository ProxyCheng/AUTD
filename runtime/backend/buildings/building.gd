class_name Building
extends Node

# 调度优先级范围(1 最低 / 9 最高;缺省值 5 由数据类 BuildingData.priority 给出)。
# 同一数值驱动两处:本建筑顶岗任务(Workshop.manning_priority)与需求仓补货
# (Bag.transport_priority)——"重要建筑既优先派人、也优先补料"。
const MIN_PRIORITY: int = 1
const MAX_PRIORITY: int = 9

var data: BuildingData
var cell: Cell
var axis: Vector2i:
	get:
		return cell.axis
var health: float
var type: String:
	get:
		return data.type
var direction: Vector2i:
	get:
		return data.direction
var state: String = "idle":
	get:
		return state
	set(in_state):
		if in_state == state:
			return
		state = in_state
		state_changed.emit()
signal state_changed()
# progress 契约:恒为 [0,1] 归一化进度(如蓄力/冷却完成度)。数据层禁止输出
# 原始秒数等任意区间值;到动画时间/播放方向的换算一律由前端 model 完成。
var progress: float = 0:
	get:
		return progress
	set(in_progress):
		if is_equal_approx(in_progress, progress):
			return
		progress = in_progress
		progress_changed.emit()
signal progress_changed()

# 调度优先级(可观察属性,§5.4):派生自 data.priority,不存第二份。
# 建筑先于 load_data 存在(见 Map.place_building 的 create→load_data→add_child 顺序),
# 故 data 为空时按数据类默认值 5 回答;此时 setter 无处可写,直接忽略。
var priority: int:
	get:
		return data.priority if data else 5
	set(in_priority):
		if not data:
			return
		# 先夹取再判同值:越界写入(如 12)夹回 9 后若与原值一致,不应发信号。
		var clamped: int = clampi(in_priority, MIN_PRIORITY, MAX_PRIORITY)
		if clamped == data.priority:
			return
		data.priority = clamped
		priority_changed.emit()
signal priority_changed()

static func create(in_type: String) -> Building:
	var building_class = load("res://runtime/backend/buildings/%s.gd" % in_type)
	return building_class.new()

func load_data(in_data: BuildingData, in_cell: Cell):
	data = in_data
	cell = in_cell

func get_type_key() -> String:
	return "Building_%s" % type

# 供 frontend 镜像的展示仓(BuildingActor 转发给 model → ItemStack)。基类无仓返回 null。
func get_display_bag() -> Bag:
	return null

# —— 物品搬运能力接口(§5.8)——
# 传送带这类"按格子找邻居"的逻辑只认 Building,而工人搬运本来就在 Bag 之间进行;
# 故规则的唯一实现在 Bag(can_accept / can_provide / deposit_rank / available_to_provide),
# 这里只把它聚合到建筑上:建筑 = "我名下任一只仓能收 / 能给"。两边判据同源,不会各写一套。
# 所有搬运动作一律走 Bag.move_to(搬实例本身,有状态物品的耐久等按件状态跟着走,§5.8)。

# 参与物品搬运的仓(基类无仓)。单仓建筑返回 [bag],多仓建筑返回名下全部仓。
func get_transfer_bags() -> Array[Bag]:
	var none: Array[Bag] = []
	return none

# 本建筑能否收下该类型(任一只仓 can_accept)。in_item_type 为空 = 任意类型。
func can_accept(in_item_type: String) -> bool:
	for bag: Bag in get_transfer_bags():
		if bag.can_accept(in_item_type):
			return true
	return false

# 本建筑能否给出该类型(任一只仓 can_provide)。in_item_type 为空 = 任意"有货且可给"的类型。
func can_provide(in_item_type: String) -> bool:
	for bag: Bag in get_transfer_bags():
		if bag.can_provide(in_item_type):
			return true
	return false

# 把 in_source 里的 in_item_type 搬进本建筑"最该接收它"的仓,返回实际搬入件数。
# 选仓顺序与 Logistics 落库一致:先比 Bag.deposit_rank(专仓 > 通配兜底),再比 deposit_priority。
func accept_from(in_source: Bag, in_item_type: String, in_amount: int) -> int:
	if not is_instance_valid(in_source) or in_amount <= 0:
		return 0
	var dest: Bag = get_accept_bag(in_item_type)
	if dest == null:
		return 0
	return in_source.move_to(dest, in_item_type, in_amount)

# 把本建筑该类型的货搬进 in_dest,返回实际搬走件数。
# in_item_type 为空 = 由本建筑挑一类可给的(在 withdraw_priority 最高的可给仓里取第一类)。
func provide_to(in_dest: Bag, in_item_type: String, in_amount: int) -> int:
	if not is_instance_valid(in_dest) or in_amount <= 0:
		return 0
	var source: Bag = _pick_provide_bag(in_item_type)
	if source == null:
		return 0
	var moved_type: String = in_item_type if not in_item_type.is_empty() else _first_providable_type(source)
	if moved_type.is_empty():
		return 0
	return source.move_to(in_dest, moved_type, in_amount)

# 接收侧选仓:只在收得下的仓里挑,deposit_rank 高者优先,同层比 deposit_priority。
# public read-only query: the frontend uses it to resolve "which bag an incoming piece will land in" and point the
# delivery animation at the right pile, without duplicating the rank/priority bag-selection rule. pure selection, no
# item movement, so it is safe to call while a delivery action is still playing.
func get_accept_bag(in_item_type: String) -> Bag:
	var best: Bag = null
	var best_rank: int = 0
	var best_priority: int = 0
	for bag: Bag in get_transfer_bags():
		if not bag.can_accept(in_item_type):
			continue
		var rank: int = bag.deposit_rank(in_item_type)
		var priority: int = bag.deposit_priority
		# best == null 兜首只候选:偏好可以为负(DEPOSIT_LAST),不能用 best_priority 的初值挡掉。
		if best == null or rank > best_rank or (rank == best_rank and priority > best_priority):
			best = bag
			best_rank = rank
			best_priority = priority
	return best

# 供给侧选仓:只在给得出的仓里挑,withdraw_priority 高者优先。
func _pick_provide_bag(in_item_type: String) -> Bag:
	var best: Bag = null
	var best_priority: int = 0
	for bag: Bag in get_transfer_bags():
		if not bag.can_provide(in_item_type):
			continue
		if best == null or bag.withdraw_priority > best_priority:
			best = bag
			best_priority = bag.withdraw_priority
	return best

# 该仓第一个"有货且可给"的类型:空类型不能直接交给 move_to,得先定下具体类型。
func _first_providable_type(in_bag: Bag) -> String:
	for entry_type: String in in_bag.types():
		if in_bag.count_of(entry_type) > 0:
			return entry_type
	return ""

# 是否允许在游戏内检视面板里删除本建筑。基类一律可删;
# 地图关键建筑(如主基地)覆写为 false —— 它被其他系统以 static 引用持有,删掉会留下悬空引用。
func is_removable() -> bool:
	return true

# 攻击范围(半边长,格子单位):以建筑所在格为中心的正方形,边长 = 2×本值。
# 返回 <=0 表示本建筑无攻击能力,前端据此不显示范围面;攻击型建筑覆写本方法。
func get_attack_range() -> float:
	return 0.0

func tick(in_delta: float):
	pass

# 容量占用率 [0,1],供 frontend 显示建筑容量条(参考实体血条)。
# 返回负值表示本建筑没有"Bag 容量"语义(如敌人出生点/主基地),前端据此隐藏容量条。
# 基类按可观察属性 stored_count/capacity 推算(料堆/弩炮/生产坊都已暴露);
# 多 Bag 建筑(如车间)覆写本方法取各 Bag 占用最满者,见 crafting_workshop.gd。
# 用 get() 鸭子访问:基类不含这些属性,只有具备它们的建筑才有容量条语义。
func occupancy_fill() -> float:
	var stored: Variant = get("stored_count")
	var cap: Variant = get("capacity")
	if stored is not int or cap is not int:
		return -1.0
	if cap <= 0:
		return -1.0
	return clampf(float(stored) / float(cap), 0.0, 1.0)
