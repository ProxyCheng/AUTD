extends Node
class_name Cell

var axis: Vector2i
var land: Land = null
var building: Building = null

func get_land() -> Land:
	return land

func get_building() -> Building:
	return building

func tick(in_delta: float):
	if building:
		building.tick(in_delta)
