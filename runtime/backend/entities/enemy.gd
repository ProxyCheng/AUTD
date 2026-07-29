class_name Enemy
extends Entity

func tick(in_delta: float):
	position = position + Vector2.RIGHT * in_delta * 0.3
