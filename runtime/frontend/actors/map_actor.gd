extends Node

var map: Map = null
var floor_actors: Dictionary = {}
var floor_actors_pool: Dictionary = {}
var building_actors: Dictionary = {}
var building_actors_pool: Dictionary = {}

func bind(in_map: Map):
	map = in_map
	map.cells_changed.connect(_on_cells_changed)

func _ready():
	var camera = get_viewport().get_camera_3d() as CameraController
	camera.viewing_axis_changed.connect(_on_viewing_axis_changed)

func _on_viewing_axis_changed(in_new_axis: Dictionary, in_old_axis: Dictionary):
	for axis in in_old_axis.keys():
		_recycle_floor_actor(axis)
		_recycle_building_actor(axis)
	for axis in in_new_axis.keys():
		_place_floor_actor(axis)
		_place_building_actor(axis)

func _on_cells_changed(in_axis: Dictionary):
	var camera = get_viewport().get_camera_3d() as CameraController
	for axis in in_axis.keys():
		if not camera or not camera.is_axis_visible(axis):
			continue
		_recycle_floor_actor(axis)
		_place_floor_actor(axis)
		_recycle_building_actor(axis)
		_place_building_actor(axis)

func _recycle_actor(in_axis: Vector2i, ref_actors: Dictionary, ref_actors_pool: Dictionary):
	var actor = ref_actors.get(in_axis)
	if not actor:
		return
	var type_key: String = actor.get_type_key()
	actor.hide()
	ref_actors.erase(in_axis)
	ref_actors_pool.get_or_add(type_key, []).append(actor)

func _place_actor(in_axis: Vector2i, in_entity, in_actor_scene: PackedScene, ref_actors: Dictionary, ref_actors_pool: Dictionary):
	if not in_entity:
		return
	var type_key = in_entity.get_type_key()
	var actors_of_type_key: Array = ref_actors_pool.get(type_key, [])
	var actor = null
	if actors_of_type_key:
		actor = actors_of_type_key.pop_back()
	else:
		actor = in_actor_scene.instantiate()
		add_child(actor)
		actor.owner = owner
	actor.bind(in_entity)
	actor.show()
	ref_actors.set(in_axis, actor)

func _recycle_floor_actor(in_axis: Vector2i):
	return _recycle_actor(in_axis, floor_actors, floor_actors_pool)

func _place_floor_actor(in_axis: Vector2i):
	var cell = map.get_cell(in_axis)
	if not cell:
		return
	var floor: Floor = cell.get_floor()
	var floor_actor_scene: PackedScene = preload("res://runtime/frontend/actors/floor_actor.tscn")
	return _place_actor(in_axis, floor, floor_actor_scene, floor_actors, floor_actors_pool)

func _recycle_building_actor(in_axis: Vector2i):
	return _recycle_actor(in_axis, building_actors, building_actors_pool)

func _place_building_actor(in_axis: Vector2i):
	var cell = map.get_cell(in_axis)
	if not cell:
		return
	var building: Building = cell.get_building()
	var building_actor_scene: PackedScene = preload("res://runtime/frontend/actors/building_actor.tscn")
	return _place_actor(in_axis, building, building_actor_scene, building_actors, building_actors_pool)
	
