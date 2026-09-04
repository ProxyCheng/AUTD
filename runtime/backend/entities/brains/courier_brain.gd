class_name CourierBrain
extends Brain

func create_action() -> Action:
	return MoveToAction.new(labor.position + Vector2.from_angle(randf() * PI * 2))
