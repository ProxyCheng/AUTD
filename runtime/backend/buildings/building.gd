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
