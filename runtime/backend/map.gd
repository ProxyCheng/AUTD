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
			cell.axis = axis
			cell.land = Land.new()
			cell.land.load_data(cell_data.land, cell)
			cell.add_child(cell.land)
			cell.land.owner = cell.owner
			add_child(cell)
			cell.owner = owner
			cells.set(axis, cell)
			changed_axis.set(axis, true)
	for i in range(data.size.x):
		for j in range(data.size.y):
			var axis: Vector2i = Vector2i(i, j)
			var cell: Cell = get_cell(axis)
			var cell_data: CellData = data.cells[j].cells[i]
			if cell_data.building:
				place_building(axis, cell_data.building, false)
	cells_changed.emit(changed_axis)

func get_cell(in_axis: Vector2i) -> Cell:
	return cells.get(in_axis)

func tick(in_delta: float):
	for cell: Cell in cells.values():
		cell.tick(in_delta)

func can_place_building(in_axis: Vector2i, in_building_data: BuildingData) -> bool:
	var cell: Cell = get_cell(in_axis)
	if not cell:
		return false
	if cell.building:
		return false
	if cell.land.type == "path":
		return false
	return true

func place_building(in_axis: Vector2i, in_building_data: BuildingData, emit_signal: bool = true) -> Building:
	var cell: Cell = get_cell(in_axis)
	cell.building = Building.create(in_building_data.type)
	cell.building.load_data(in_building_data, cell)
	cell.add_child(cell.building)
	cell.building.owner = cell.owner
	if emit_signal:
		cells_changed.emit({ in_axis: true })
	return cell.building

# 删除指定格的建筑:清引用 → 广播(驱动 frontend 回收 actor)→ 销毁节点
# (建筑/子类 _exit_tree 负责注销参与逻辑的 bag、取消 worker 请求)。无建筑则空操作。
func remove_building(in_axis: Vector2i):
	var cell: Cell = get_cell(in_axis)
	if not cell or not cell.building:
		return
	var building: Building = cell.building
	cell.building = null
	cells_changed.emit({ in_axis: true })
	building.queue_free()
