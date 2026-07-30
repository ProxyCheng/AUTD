@tool
extends Resource
class_name MapData

@export
var size: Vector2i

@export
var cells: Array[CellRowData]

@export_tool_button("Fill Cells")
var fill_cells = func():
	while cells.size() < size.y:
		var cell_row = CellRowData.new()
		cells.append(cell_row)
	while cells.size() > size.y:
		cells.pop_back()
	for cell_row in cells:
		var cells_of_row = cell_row.cells
		while cells_of_row.size() < size.x:
			var cell = CellData.new()
			cells_of_row.append(cell)
		while cells_of_row.size() > size.x:
			cells_of_row.pop_back()
		for cell: CellData in cells_of_row:
			var land: LandData = LandData.new()
			land.type = "dirt"
			cell.land = land
	emit_changed()
	notify_property_list_changed()

func get_cell(in_position: Vector2i) -> CellData:
	return cells[in_position.y].cells[in_position.x]
