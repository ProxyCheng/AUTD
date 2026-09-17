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
