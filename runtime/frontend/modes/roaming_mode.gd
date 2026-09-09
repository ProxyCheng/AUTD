class_name RoamingMode
extends Mode

# 漫游模式:自由探索 + 点选已放置建筑打开检视面板。
# B 键切到建造模式;点击落点格若有建筑,经 LevelActor.inspect_building 打开 GUI 面板。

func tick(in_delta: float):
	if Input.is_key_pressed(KEY_B):
		owner.set_mode(&"building")
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var axis = get_pointing_axis()
	if axis == null:
		return
	var map: Map = Level.current.map
	var cell: Cell = map.get_cell(axis)
	if not cell or not cell.building:
		return
	owner.inspect_building(cell.building)

func get_pointing_axis():
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d()
	var mouse_position: Vector2 = viewport.get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mouse_position)
	var direction: Vector3 = camera.project_ray_normal(mouse_position)
	var hit_position = ray_intersects_y0(origin, direction)
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
