class_name Map

var data: MapData
var cells: Dictionary[Vector2i, Cell]

signal cells_changed(axis: Dictionary[Vector2i, bool])

func load_data(in_data: MapData):
	data = in_data
	var changed_axis: Dictionary = {}
	for axis in cells.keys():
		changed_axis.set(axis, true)
	cells.clear()
	for i in range(data.size.x):
		for j in range(data.size.y):
			var axis: Vector2i = Vector2i(i, j)
			var cell: Cell = Cell.new()
			var cell_data: CellData = data.cells[j].cells[i]
			cell.load_data(cell_data, axis)
			cells.set(axis, cell)
			changed_axis.set(axis, true)
	cells_changed.emit(changed_axis)

func get_cell(in_axis: Vector2i) -> Cell:
	return cells.get(in_axis)
