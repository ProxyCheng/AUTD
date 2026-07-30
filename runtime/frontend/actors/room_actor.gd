extends Node
class_name RoomActor

var room: Room = null
var entity_actors: Dictionary = {}
var entity_actors_pool: Dictionary = {}

func bind(in_room: Room):
	room = in_room
	room.entities_changed.connect(_on_entities_changed)

func _on_entities_changed(in_added_entity_ids: Array, in_removed_entity_ids: Array):
	var camera = get_viewport().get_camera_3d() as CameraController
	for entity_id in in_removed_entity_ids:
		_recycle_entity_actor(entity_id)
	for entity_id in in_added_entity_ids:
		var entity: Entity = room.get_entity(entity_id)
		if not entity:
			continue
		if not camera or not camera.is_position_visible(entity.position):
			continue
		_place_entity_actor(entity_id)

func _place_entity_actor(in_entity_id: int):
	var entity: Entity = room.get_entity(in_entity_id)
	if not entity:
		return
	var type_key: String = entity.get_type_key()
	var entity_actors_of_type_key: Array = entity_actors_pool.get(type_key, [])
	var entity_actor: EntityActor = null
	if entity_actors_of_type_key:
		entity_actor = entity_actors_of_type_key.pop_back()
	else:
		var entity_scene: PackedScene = preload("res://runtime/frontend/actors/entity_actor.tscn")
		entity_actor = entity_scene.instantiate()
		add_child(entity_actor)
		entity_actor.owner = owner
	entity_actor.bind(entity)
	entity_actor.show()
	entity_actors.set(in_entity_id, entity_actor)

func _recycle_entity_actor(in_entity_id: int):
	var entity_actor: EntityActor = entity_actors.get(in_entity_id)
	if not entity_actor:
		return
	var type_key: String = entity_actor.get_type_key()
	entity_actor.bind(null)
	entity_actor.hide()
	entity_actors.erase(in_entity_id)
	entity_actors_pool.get_or_add(type_key, []).append(entity_actor)
