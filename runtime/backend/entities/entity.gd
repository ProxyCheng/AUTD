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

var move_speed: float = 0.1

var action: Action = null

const ENTITY_CLASSES = {
	"slime": preload("res://runtime/backend/entities/enemy.gd"),
}

static func create(in_type: String) -> Entity:
	var entity_class = ENTITY_CLASSES.get(in_type, Entity)
	var entity: Entity = entity_class.new()
	entity.type = in_type
	return entity

func tick(in_delta: float):
	var remained_time: float = in_delta
	while remained_time > 0:
		if not action:
			action = create_action()
			add_child(action)
			action.owner = owner
			action.set_entity(self)
		action.enter()
		var action_status: ActionStatus = action.tick(remained_time)
		remained_time = action_status.remained_time
		if not action_status.is_running():
			action.leave()
			remove_child(action)
			action.queue_free()
			action = null

func get_type_key() -> String:
	return "Entity_%s" % type

func create_action() -> Action:
	return IdleAction.new()

func take_damage(in_damage: float):
	Level.current.room.remove_entity(id)

func _init():
	id = next_id
	next_id += 1
