class_name Entity

static var next_id: int = 1

var id: int = 0
var type: String = ""
var position: Vector2:
	set(in_position):
		position = in_position
		position_changed.emit()
	get:
		return position
signal position_changed()

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
