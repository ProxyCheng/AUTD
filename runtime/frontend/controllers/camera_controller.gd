extends Camera3D
class_name CameraController

@export
var move_speed: float = 5

@export
var rotation_speed: float = 2

@export
var smooth_movement: bool = true

@export
var smooth_factor: float = 0.1

var target_position: Vector3
var target_yaw: float

func _ready():
	target_position = global_position
	target_yaw = rotation.y

func _process(delta: float) -> void:
	var movement_input = _get_movement_input()
	var rotation_input = _get_rotation_input()
	_handle_movement(movement_input, delta)
	_handle_rotation(rotation_input, delta)

func _get_movement_input() -> Vector3:
	var input_dir = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.z += 1
	if Input.is_action_pressed("move_backward"):
		input_dir.z -= 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	return forward * input_dir.z + right * input_dir.x

func _get_rotation_input() -> float:
	var rotation_input = 0.0
	if Input.is_action_pressed("rotate_left"):
		rotation_input += 1
	if Input.is_action_pressed("rotate_right"):
		rotation_input -= 1
	return rotation_input
	
func _handle_movement(input_vector: Vector3, delta: float):
	if not smooth_movement and input_vector.length_squared() == 0:
		return
	var movement = input_vector * move_speed * delta
	if smooth_movement:
		target_position += movement
		global_position = global_position.lerp(target_position, smooth_factor)
	else:
		global_position += movement

func _handle_rotation(rotation_input: float, delta: float):
	if not smooth_movement and rotation_input == 0:
		return
	var rotation_amount = rotation_input * rotation_speed * delta
	if smooth_movement:
		target_yaw += rotation_amount
		rotation.y = lerp(rotation.y, target_yaw, smooth_factor)
	else:
		rotate_y(rotation_amount)
