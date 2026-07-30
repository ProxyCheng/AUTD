extends Node3D
class_name EntityActor

var entity: Entity = null
var type: String = ""
var model: Node3D = null
var state: String = ""

func bind(in_entity: Entity):
	if entity:
		entity.position_changed.disconnect(_on_entity_position_changed)
		entity.direction_changed.disconnect(_on_entity_direction_changed)
		entity.state_changed.disconnect(_on_entity_state_changed)
	entity = in_entity
	if not entity:
		return
	if entity.type != type:
		_on_entity_type_changed()
	_on_entity_position_changed()
	_on_entity_direction_changed()
	if entity.state != state:
		_on_entity_state_changed()
	entity.position_changed.connect(_on_entity_position_changed)
	entity.direction_changed.connect(_on_entity_direction_changed)
	entity.state_changed.connect(_on_entity_state_changed)
	name = "%d (%s)" % [entity.id, get_type_key()]
	
func get_type_key() -> String:
	return "Entity_%s" % type
	
func _on_entity_position_changed():
	position = Vector3(entity.position.x, 0, entity.position.y)

func _on_entity_direction_changed():
	look_at(global_position + Vector3(entity.direction.x, 0, entity.direction.y))

func _on_entity_type_changed():
	type = entity.type
	if model:
		remove_child(model)
		model.queue_free()
	var entity_path: String = "res://runtime/frontend/models/entities/%s/%s.tscn" % [type, type]
	var entity_scene: PackedScene = load(entity_path)
	model = entity_scene.instantiate()
	if model:
		add_child(model)
		model.owner = owner
		model.scale = Vector3.ONE * 0.3

func _on_entity_state_changed():
	state = entity.state
	model.set_state(state)
