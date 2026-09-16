class_name Entity
extends Node

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

# 实际移速:默认即 move_speed;子类可覆写以表达派生减速(如 Labor 负重)。
# 移动类叶子一律经此取值,不直接读 move_speed。
func get_move_speed() -> float:
	return move_speed

static func create(in_type: String) -> Entity:
	var entity_class = load("res://runtime/backend/entities/%s.gd" % in_type)
	var entity: Entity = entity_class.new()
	entity.type = in_type
	return entity

func get_type_key() -> String:
	return "Entity_%s" % type

func _init():
	id = next_id
	next_id += 1

func _ready():
	name = "%d (%s)" % [id, type]
