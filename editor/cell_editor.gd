@tool
class_name CellEditor
extends Node3D

@export
var grid: Vector2i
@export
var data: CellData

var building_editor: Node3D

func load_data(in_data: CellData):
	data = in_data
	
	var path = "res://runtime/frontend/textures/load_%s.png" % data.load.type
	var texture
	if ResourceLoader.exists(path):
		texture = load(path) as CompressedTexture2D
	%load_editor.mesh.material.albedo_texture = texture
	
	if building_editor:
		remove_child(building_editor)
		building_editor.queue_free()
		building_editor = null
	var building_data = data.building
	if building_data:
		var building_scene = load("res://runtime/frontend/models/buildings/%s/%s.tscn" % [data.building.type, data.building.type]) as PackedScene
		building_editor = building_scene.instantiate() as Node3D
		add_child(building_editor)
		building_editor.owner = owner

func set_grid(in_grid: Vector2i):
	grid = in_grid
	position = Vector3(grid.x, 0, grid.y)

func update_name():
	name = "(%d, %d) %s" % [grid.x, grid.y, data.land.type]
