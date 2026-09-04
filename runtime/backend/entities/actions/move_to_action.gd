extends Action
class_name MoveToAction

var target_position: Vector2 = Vector2.ZERO

func _init(in_target_position: Vector2):
	super._init()
	target_position = in_target_position

func enter():
	entity.direction = (target_position - entity.position).normalized()
	entity.state = "walk"

func tick(in_delta: float) -> ActionStatus:
	if entity.move_speed <= 0:
		return ActionStatus.failure(in_delta)
	var estimate_time: float = (target_position - entity.position).length() / entity.move_speed
	if estimate_time > in_delta:
		entity.position = entity.position.lerp(target_position, in_delta / estimate_time)
		return ActionStatus.running()
	entity.position = target_position
	return ActionStatus.success(in_delta - estimate_time)
