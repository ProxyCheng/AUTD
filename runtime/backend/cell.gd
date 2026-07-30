extends Node
class_name Cell

var data: CellData = null
var axis: Vector2i
var land: Land = null
var building: Building = null

func load_data(in_data: CellData, in_axis: Vector2i):
	data = in_data
	axis = in_axis
	land = Land.new()
	land.load_data(data.land, self)
	add_child(land)
	land.owner = owner
	if data.building:
		building = Building.create(data.building.type)
		building.load_data(data.building, self)
		add_child(building)
		building.owner = owner

func get_type_key() -> String:
	return data.type

func get_land() -> Land:
	return land

func get_building() -> Building:
	return building

func tick(in_delta: float):
	if building:
		building.tick(in_delta)
