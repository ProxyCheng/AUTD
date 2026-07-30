extends Node3D

func set_state(in_state: StringName):
	%animation.play("slime_%s/Take 001" % in_state)
