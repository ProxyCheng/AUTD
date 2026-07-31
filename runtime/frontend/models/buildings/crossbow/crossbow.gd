extends Node3D

func _ready():
	%AnimationPlayer.play(&"boneAction_001")
	%AnimationPlayer.pause()

func set_state(in_state: String):
	pass

func set_progress(in_progress: int):
	var length = %AnimationPlayer.current_animation_length()
	%AnimationPlayer.seek(in_progress * length, true)
