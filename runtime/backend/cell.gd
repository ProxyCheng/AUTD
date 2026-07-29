class_name Cell

var data: CellData = null
var axis: Vector2i
var floor: Floor = null
var building: Building = null

func load_data(in_data: CellData, in_axis: Vector2i):
	data = in_data
	axis = in_axis
	floor = Floor.new()
	floor.load_data(data.floor, self)
	if data.building:
		building = Building.create(data.building.type)
		building.load_data(data.building, self)

func get_type_key() -> String:
	return data.type

func get_floor() -> Floor:
	return floor

func get_building() -> Building:
	return building

func tick(in_delta: float):
	if building:
		building.tick(in_delta)
