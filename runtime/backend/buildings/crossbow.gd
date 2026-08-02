extends Building

var fire_timer: float = 0

func tick(in_delta: float):
	fire_timer += in_delta
	while fire_timer > 3:
		fire_timer -= 3
		fire(fire_timer)

func fire(in_delta: float):
	var room: Room = Level.current.room
	var entities: Array = room.get_entities_in_rect(Rect2(axis.x - 3, axis.y - 3, 6, 6))
	for entity: Entity in entities:
		if entity is not Enemy:
			continue
		if not entity.is_alive():
			continue
		entity.take_damage(Damage.physical(100))
		break
