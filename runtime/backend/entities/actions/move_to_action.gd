extends Action
class_name MoveToAction

var target_position: Vector2 = Vector2.ZERO

func _init(in_target_position: Vector2):
	target_position = in_target_position

func enter():
	entity.direction = (target_position - entity.position).normalized()
	entity.state = "walk"

func tick(in_delta: float) -> float:
	if entity.move_speed <= 0:
		return -1
	var estimate_time: float = (target_position - entity.position).length() / entity.move_speed
	if estimate_time > in_delta:
		entity.position = entity.position.lerp(target_position, in_delta / estimate_time)
		return 0
	entity.position = target_position
	return in_delta - estimate_time
