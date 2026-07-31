class_name RoamingMode
extends Mode

@export
var jack: int = 0

func tick(in_delta: float):
	if Input.is_key_pressed(KEY_B):
		owner.set_mode(&"building")
