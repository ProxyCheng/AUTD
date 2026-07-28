@tool
extends Node3D
class_name BuildingActor

@export
var data: BuildingData

func load_data(in_data: BuildingData):
	data = in_data
	refresh()

func refresh():
	var building_path = "res://runtime/frontend/models/buildings/%s/%s.tscn" % [data.type, data.type]
	var building_scene = load(building_path) as PackedScene
	var building_actor = building_scene.instantiate()
	add_child(building_actor)
	building_actor.owner = owner
