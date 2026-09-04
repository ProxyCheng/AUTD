class_name CrossbowModel
extends Node3D

func _ready():
	%AnimationPlayer.play(&"bone|boneAction_001")
	%AnimationPlayer.pause()

func set_state(in_state: String):
	pass

func set_progress(in_progress: float):
	var length = %AnimationPlayer.current_animation_length
	%AnimationPlayer.seek((1 - in_progress) * length, true)

func set_target_position(in_position: Vector3):
	var direction: Vector3 = in_position - global_position
	var angle: float = direction.signed_angle_to(Vector3.BACK, Vector3.DOWN)
	%cog_top.rotation.z = angle
	%cog_left.rotation.x = angle * 8 / 5
	%cog_right.rotation.x = -angle * 8 / 5
	var distance: float = global_position.distance_squared_to(in_position)
	var max_angle: float = 40 * PI / 180
	%body.rotation.x = max_angle * (1 - (distance - 1) / 5)
