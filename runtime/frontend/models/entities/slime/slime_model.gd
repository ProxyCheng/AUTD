class_name SlimeModel
extends Node3D

var state: StringName = &""

func set_state(in_state: StringName):
	state = in_state
	%animation.play("slime_%s/Take 001" % in_state)

func _on_animation_animation_finished(in_anim_name: StringName) -> void:
	match state:
		&"hit":
			set_state(&"dizzy")
