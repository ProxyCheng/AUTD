class_name Enemy
extends Entity

func _init():
	super._init()
	direction = Vector2.RIGHT
	state = "walk"

func tick(in_delta: float):
	position += Vector2.RIGHT * in_delta * 0.3
	if position.x > 3:
		Level.current.room.remove_entity(id)
