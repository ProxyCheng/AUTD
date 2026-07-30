extends Node
class_name Land

var data: LandData
var type: String:
	get:
		return data.type if data else ""
var cell: Cell
var axis: Vector2i:
	get:
		return cell.axis if cell else Vector2i.ZERO

func load_data(in_data: LandData, in_cell: Cell):
	data = in_data
	cell = in_cell

func get_type_key() -> String:
	return "land_%s" % type
