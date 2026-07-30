extends Node
class_name Entity

static var next_id: int = 1

var id: int = 0
var type: String = ""

var position: Vector2:
	get:
		return position
	set(in_position):
		if in_position == position:
			return
		position = in_position
		position_changed.emit()
signal position_changed()

var direction: Vector2 = Vector2.UP:
	get:
		return direction
	set(in_direction):
		if in_direction == direction:
			return
		direction = in_direction
		direction_changed.emit()
signal direction_changed()

var state: String = "idle":
	get:
		return state
	set(in_state):
		if in_state == state:
			return
		state = in_state
		state_changed.emit()
signal state_changed()

const ENTITY_CLASSES = {
	"slime": preload("res://runtime/backend/entities/enemy.gd"),
}

static func create(in_type: String) -> Entity:
	var entity_class = ENTITY_CLASSES.get(in_type, Entity)
	var entity: Entity = entity_class.new()
	entity.type = in_type
	return entity

func tick(in_delta: float):
	pass

func get_type_key() -> String:
	return "Entity_%s" % type

func _init():
	id = next_id
	next_id += 1
