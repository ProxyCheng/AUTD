class_name Building
extends Node

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

static func create(in_type: String) -> Building:
	var building_class = load("res://runtime/backend/buildings/%s.gd" % in_type)
	return building_class.new()

func load_data(in_data: BuildingData, in_cell: Cell):
	data = in_data
	cell = in_cell

func get_type_key() -> String:
	return "Building_%s" % type

func tick(in_delta: float):
	pass
