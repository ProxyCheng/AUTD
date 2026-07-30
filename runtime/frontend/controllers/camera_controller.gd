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

@export
var zoom_speed: float = 2.0

var target_position: Vector3
var target_yaw: float
var yaw: float
var zoom_input: float = 0.0

# Viewing axis tracking
var _visible_cells: Dictionary = {}       # current frame's visible cells (for external queries)
var _prev_visible_cells: Dictionary = {}
var _initialized: bool = false

signal viewing_axis_changed(new_axis: Dictionary[Vector2i, bool], old_axis: Dictionary[Vector2i, bool])

func _ready():
	target_position = global_position
	target_yaw = rotation.y
	yaw = rotation.y

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_input += 1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_input -= 1

func _process(delta: float) -> void:
	var movement_input = _get_movement_input()
	var rotation_input = _get_rotation_input()
	_handle_movement(movement_input, delta)
	_handle_rotation(rotation_input, delta)
	_handle_zoom(delta)
	_update_viewing_axis()

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
		yaw = lerp(yaw, target_yaw, smooth_factor)
		rotation.y = yaw
	else:
		rotate_y(rotation_amount)

func _handle_zoom(delta: float) -> void:
	if zoom_input == 0:
		return
	var zoom_vector = -global_transform.basis.z * zoom_input * zoom_speed * delta
	if smooth_movement:
		target_position += zoom_vector
	else:
		global_position += zoom_vector
	zoom_input = 0.0

# -------------------------------------------------------------------------- #
# Viewing Axis — determines which grid cells (cell size=1 on y=0 plane) are
# visible from the camera, and emits changes each frame via _process().
# -------------------------------------------------------------------------- #
func _update_viewing_axis() -> void:
	var current_visible := _get_visible_cells()
	_visible_cells = current_visible

	if not _initialized:
		_prev_visible_cells = current_visible
		_initialized = true
		return

	var new_cells: Dictionary = {}
	var removed_cells: Dictionary = {}

	for cell in current_visible:
		if not _prev_visible_cells.has(cell):
			new_cells[cell] = true

	for cell in _prev_visible_cells:
		if not current_visible.has(cell):
			removed_cells[cell] = true

	if not new_cells.is_empty() or not removed_cells.is_empty():
		viewing_axis_changed.emit(new_cells, removed_cells)

	_prev_visible_cells = current_visible


# Public query — lets external code (e.g. map_actor._on_cells_changed) skip
# cells that are outside the current camera frustum.
func is_axis_visible(axis: Vector2i) -> bool:
	if _visible_cells.is_empty():
		_visible_cells = _get_visible_cells()
	return _visible_cells.has(axis)

func is_position_visible(in_position: Vector2) -> bool:
	return is_axis_visible(in_position.round())

# Project 4 screen-corner rays onto y=0, then for every cell in the AABB
# of the resulting ground quadrilateral test all 4 corners with a 2D
# convex-polygon contain-ment test.  This avoids the sign-convention
# ambiguity of get_frustum() and correctly handles edge cells.
func _get_visible_cells() -> Dictionary:
	var viewport := get_viewport()
	var screen_size := viewport.get_visible_rect().size

	# 4 screen corners in UV winding order (TL→TR→BR→BL) so the projected
	# ground quadrilateral is convex rather than a bow-tie.
	var uvs := [
		Vector2(0, 0),
		Vector2(screen_size.x, 0),
		Vector2(screen_size.x, screen_size.y),
		Vector2(0, screen_size.y),
	]

	# Ground-plane intersection points → convex polygon on (x, z)
	var ground_verts: Array[Vector2] = []
	for uv in uvs:
		var origin := project_ray_origin(uv)
		var dir := project_ray_normal(uv)
		if dir.y < -0.0001:
			var t := -origin.y / dir.y
			if t > 0.0:
				var hit := origin + t * dir
				ground_verts.append(Vector2(hit.x, hit.z))

	if ground_verts.size() < 3:
		return {}

	# AABB of ground polygon
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for v in ground_verts:
		min_pos.x = min(min_pos.x, v.x)
		min_pos.y = min(min_pos.y, v.y)
		max_pos.x = max(max_pos.x, v.x)
		max_pos.y = max(max_pos.y, v.y)

	# Include camera position projected to ground
	min_pos.x = min(min_pos.x, global_position.x)
	min_pos.y = min(min_pos.y, global_position.z)
	max_pos.x = max(max_pos.x, global_position.x)
	max_pos.y = max(max_pos.y, global_position.z)

	# Safety margin for cells that straddle the polygon boundary
	var margin := 1.0
	min_pos -= Vector2(margin, margin)
	max_pos += Vector2(margin, margin)

	# Clamp to a reasonable world range
	var max_range := 500.0
	min_pos.x = clamp(min_pos.x, -max_range, max_range)
	min_pos.y = clamp(min_pos.y, -max_range, max_range)
	max_pos.x = clamp(max_pos.x, -max_range, max_range)
	max_pos.y = clamp(max_pos.y, -max_range, max_range)

	var x_from := floori(min_pos.x)
	var x_to := ceili(max_pos.x)
	var z_from := floori(min_pos.y)
	var z_to := ceili(max_pos.y)

	# Far-plane distance check (distance along view direction)
	var cam_pos := global_position
	var cam_dir := -global_transform.basis.z
	var far_dist := far  # Camera3D's far property

	var max_cells := 20000
	var cell_count := 0
	var visible: Dictionary = {}

	for x in range(x_from, x_to + 1):
		for z in range(z_from, z_to + 1):
			if cell_count >= max_cells:
				break

			var fx := float(x)
			var fz := float(z)
			if _cell_any_corner_in_view(fx, fz, ground_verts, cam_pos, cam_dir, far_dist):
				visible[Vector2i(x, z)] = true
				cell_count += 1

		if cell_count >= max_cells:
			break

	return visible


# Test whether the axis-aligned 1×1 cell centered at (cx, cz) intersects
# the convex ground polygon at all (SAT-based).  This catches cells that
# are only visible by a sliver because a polygon edge slices through them
# without including any corner — something pure corner-sampling misses.
static func _cell_intersects_ground(cx: float, cz: float, verts: Array[Vector2]) -> bool:
	var n := verts.size()
	if n < 3:
		return false

	const EPS := 0.0001

	# ---- helper: project verts + cell onto an axis and test separation ----
	var axes: Array[Vector2] = []
	# Rectangle axes
	axes.append(Vector2(1, 0))
	axes.append(Vector2(0, 1))
	# Polygon edge normals
	for i in range(n):
		var a := verts[i]
		var b := verts[(i + 1) % n]
		var edge := b - a
		axes.append(Vector2(-edge.y, edge.x).normalized())

	for axis in axes:
		var nx := axis.x
		var ny := axis.y
		# Project cell (half-size = 0.5)
		var cell_center_p: float = cx * nx + cz * ny
		var cell_min: float = cell_center_p - 0.5 * (abs(nx) + abs(ny))
		var cell_max: float = cell_center_p + 0.5 * (abs(nx) + abs(ny))
		# Project polygon
		var poly_min :=  INF
		var poly_max := -INF
		for v in verts:
			var p := v.x * nx + v.y * ny
			if p < poly_min: poly_min = p
			if p > poly_max: poly_max = p
		# Gap → separating axis → no intersection
		if cell_max < poly_min - EPS or poly_max < cell_min - EPS:
			return false

	return true


# Test all 4 corners of cell [cx, cx+1] × {0} × [cz, cz+1] against the
# ground-plane polygon and far-plane.  Returns true if ANY corner passes.
static func _cell_any_corner_in_view(
	cx: float, cz: float,
	ground_verts: Array[Vector2],
	cam_pos: Vector3, cam_dir: Vector3, far_dist: float,
) -> bool:
	# First check whether the cell as a whole intersects the ground polygon
	if not _cell_intersects_ground(cx, cz, ground_verts):
		return false

	# Now check far-plane: at least one corner must be within far distance
	var corners := [
		Vector2(cx - 0.5, cz - 0.5),
		Vector2(cx + 0.5, cz - 0.5),
		Vector2(cx - 0.5, cz + 0.5),
		Vector2(cx + 0.5, cz + 0.5),
	]
	for p in corners:
		var to_cell := Vector3(p.x, 0.0, p.y) - cam_pos
		if to_cell.dot(cam_dir) <= far_dist:
			return true
	# All corners are beyond far plane → treat as invisible
	return false
