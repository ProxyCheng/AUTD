extends Node3D
class_name EntityActor

var entity: Entity = null
var type: String = ""
var entity_model: Node3D = null

signal position_changed()

func bind(in_entity: Entity):
	if entity:
		entity.position_changed.disconnect(_on_entity_position_changed)
	entity = in_entity
	if not entity:
		return
	if entity.type != type:
		type = entity.type
		_on_type_changed()
	if entity.position != Vector2(position.x, position.z):
		_on_entity_position_changed()
	entity.position_changed.connect(_on_entity_position_changed)
	
func _on_entity_position_changed():
	position = Vector3(entity.position.x, 0, entity.position.y)
	position_changed.emit()

func _on_type_changed():
	if entity_model:
		remove_child(entity_model)
		entity_model.queue_free()
	var entity_path: String = "res://runtime/frontend/models/entities/%s/%s.tscn" % [type, type]
	var entity_scene: PackedScene = load(entity_path)
	entity_model = entity_scene.instantiate()
	if entity_model:
		add_child(entity_model)
		entity_model.owner = owner
