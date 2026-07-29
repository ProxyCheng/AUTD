class_name Floor

var data: FloorData
var type: String:
	get:
		return data.type
var cell: Cell
var axis: Vector2i:
	get:
		return cell.axis

func load_data(in_data: FloorData, in_cell: Cell):
	data = in_data
	cell = in_cell

func get_type_key() -> String:
	return "floor_%s" % data.type
