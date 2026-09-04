extends Building

var fire_timer: float = 0
var target: Entity:
	get:
		return target
	set(in_target):
		if in_target == target:
			return
		target = in_target
		target_changed.emit()
signal target_changed()

var input_bag: Bag

func _ready():
	input_bag = Bag.new()
	add_child(input_bag)
	input_bag.owner = owner
	input_bag.item_type = "arrow"
	input_bag.disired_min_count = input_bag.disired_max_count

func tick(in_delta: float):
	fire_timer += in_delta
	target = find_target()
	while fire_timer > 3:
		fire_timer -= 3
		fire(fire_timer)

func fire(in_delta: float):
	var room: Room = Level.current.room
	if not target:
		return
	var arrow: Arrow = Entity.create("arrow")
	arrow.position = Vector2(axis.x, axis.y)
	arrow.move_speed = 10
	arrow.set_target_entity(target)
	room.add_entity(arrow)

func find_target() -> Entity:
	var room: Room = Level.current.room
	var entities: Array = room.get_entities_in_rect(Rect2(axis.x - 3, axis.y - 3, 6, 6))
	for entity: Entity in entities:
		if entity is not Enemy:
			continue
		if not entity.is_alive():
			continue
		return entity
	return null
