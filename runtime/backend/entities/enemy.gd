class_name Enemy
extends Entity

var die_timer: float = 0

func _init():
	super._init()
	direction = Vector2.RIGHT
	state = "walk"

func tick(in_delta: float):
	match state:
		"walk":
			position += Vector2.RIGHT * in_delta * 0.3
			if position.x > 3:
				state = "die"
		"die":
			die_timer += in_delta
			if die_timer > 1:
				Level.current.room.remove_entity(id)
