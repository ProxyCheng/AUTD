extends Node3D
class_name BuildingActor

var building: Building = null
var type: String = ""
var building_model: Node3D = null
var axis: Vector2i = Vector2i.ZERO
var direction: Vector2i = Vector2i.UP

func bind(in_building: Building):
	building = in_building
	if building.type != type:
		type = building.type
		_on_type_changed()
	if building.axis != axis:
		axis = building.axis
		_on_axis_changed()
	if building.direction != direction:
		direction = building.direction
		_on_direction_changed()
	_update_direction()

func get_type_key() -> String:
	return "Building_%s" % type

func _on_type_changed():
	if building_model:
		remove_child(building_model)
		building_model.queue_free()
	var building_path: String = "res://runtime/frontend/models/buildings/%s/%s.tscn" % [type, type]
	var building_scene: PackedScene = load(building_path)
	building_model = building_scene.instantiate()
	if building_model:
		add_child(building_model)
		building_model.owner = owner

func _on_axis_changed():
	position = Vector3(axis.x, 0, axis.y)

func _on_direction_changed():
	look_at(global_position + Vector3(direction.x, 0, direction.y))

func _process(delta: float):
	_update_direction()
	
func _update_direction():
	if not building_model:
		return
	if not building_model.has_method(&"set_target_position"):
		return
	if not building:
		return
	if not building.target:
		return
	var target_position = building.target.position
	building_model.set_target_position(Vector3(target_position.x, 0, target_position.y))
