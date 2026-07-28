@tool
extends Node
class_name Map

func load_data(in_data: MapData):
	clear()
	for i in range(in_data.size.x):
		for j in range(in_data.size.y):
			var cell_scene: PackedScene = preload("res://runtime/frontend/actors/cell_actor.tscn")
			var cell_actor: CellActor = cell_scene.instantiate()
			var cell_data = in_data.get_cell(Vector2i(i, j))
			cell_actor.load_data(cell_data)
			cell_actor.set_grid(Vector2i(i, j))
			cell_actor.update_name()
			add_child(cell_actor)
			cell_actor.owner = owner

func clear():
	for child in get_children():
		child.queue_free()
		remove_child(child)
