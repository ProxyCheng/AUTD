class_name Arrow
extends Entity

var damage: Damage = Damage.physical(10)

var target_entity_ref: WeakRef = null
var target_position: Vector2 = Vector2.ZERO
var target_entity: Entity:
	get:
		if target_entity_ref:
			return target_entity_ref.get_ref()
		return null

func set_target_entity(in_target_entity: Entity):
	target_entity_ref = weakref(in_target_entity)
	target_position = in_target_entity.position
	direction = (target_position - position).normalized()

func tick(in_delta: float):
	if target_entity:
		target_position = target_entity.position
	position = position.move_toward(target_position, move_speed * in_delta)
	if position.is_equal_approx(target_position):
		if target_entity:
			target_entity.take_damage(damage)
		Level.current.room.remove_entity(id)
