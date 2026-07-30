extends Node
class_name Map

var data: MapData = null
var cells: Dictionary = {}

signal cells_changed(axis: Dictionary[Vector2i, bool])

func load_data(in_data: MapData):
	data = in_data
	var changed_axis: Dictionary = {}
	for axis in cells.keys():
		changed_axis.set(axis, true)
	for cell in get_children():
		remove_child(cell)
		cell.queue_free()
	cells.clear()
	for i in range(data.size.x):
		for j in range(data.size.y):
			var axis: Vector2i = Vector2i(i, j)
			var cell: Cell = Cell.new()
			cell.name = "Cell_%d_%d" % [i, j]
			var cell_data: CellData = data.cells[j].cells[i]
			cell.load_data(cell_data, axis)
			add_child(cell)
			cell.owner = owner
			cells.set(axis, cell)
			changed_axis.set(axis, true)
	cells_changed.emit(changed_axis)

func get_cell(in_axis: Vector2i) -> Cell:
	return cells.get(in_axis)

func tick(in_delta: float):
	for cell: Cell in cells.values():
		cell.tick(in_delta)
