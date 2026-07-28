@tool
extends Node3D
class_name CellActor

@export
var grid: Vector2i
@export
var data: CellData

var building_actor: BuildingActor

func load_data(in_data: CellData):
	data = in_data
	%floor_actor.load_data(data.floor)
	
	if building_actor:
		remove_child(building_actor)
		building_actor.queue_free()
		building_actor = null
	var building_data = data.building
	if building_data:
		var building_scene = preload("res://runtime/frontend/actors/building_actor.tscn") as PackedScene
		building_actor = building_scene.instantiate() as BuildingActor
		building_actor.load_data(building_data)
		add_child(building_actor)
		building_actor.owner = owner
		building_actor.rotate_y(PI / 2)
		print(building_actor.rotation)

func set_grid(in_grid: Vector2i):
	grid = in_grid
	position = Vector3(grid.x, 0, grid.y)

func update_name():
	name = "(%d, %d) %s" % [grid.x, grid.y, data.floor.type]
