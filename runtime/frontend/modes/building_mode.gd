class_name BuildingMode
extends Mode

func _ready():
	$"ui".hide()

func enter():
	$"ui".show()

func tick(in_delta: float):
	if Input.is_key_pressed(KEY_ESCAPE):
		owner.set_mode(&"roaming")
	var axis = get_pointing_axis()
	var cell = Level.current.map.get_cell(axis)
	print(cell.land.type if cell and cell.land else "")
	
func get_pointing_axis():
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d()
	var mouse_position: Vector2 = viewport.get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mouse_position)
	var direction: Vector3 = camera.project_ray_normal(mouse_position)
	var hit_position: Vector3 = ray_intersects_y0(origin, direction)
	if not hit_position:
		return null
	return Vector2i(round(hit_position.x), round(hit_position.z))

func ray_intersects_y0(in_origin: Vector3, in_direction: Vector3):
	if is_zero_approx(in_direction.y):
		return null
	var t: float = -in_origin.y / in_direction.y
	if t < 0:
		return null
	return in_origin + in_direction * t

func leave():
	$"ui".hide()
