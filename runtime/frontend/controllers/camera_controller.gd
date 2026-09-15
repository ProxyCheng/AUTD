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

# —— 触屏手势 ——
# 单指/鼠标拖动超过该像素阈值才判为"拖动相机";否则松手算作点击(tap)。
@export
var tap_max_distance: float = 16.0

# 双指捏合缩放灵敏度(屏幕像素 → 沿视线前进的距离)。
@export
var pinch_zoom_speed: float = 0.02

# 双指旋转灵敏度(屏幕夹角弧度 → 相机偏航角弧度)。
@export
var twist_rotate_speed: float = 1.0

var target_position: Vector3
var target_yaw: float
var yaw: float
var zoom_input: float = 0.0

# 桌面鼠标在统一指针表里的伪索引(真实触摸 index >= 0,不会冲突)。
const _MOUSE_POINTER: int = -2

# 按下中的指针 { pointer_index: Vector2 };空表示当前无手势。
var _pointers: Dictionary = {}
# 单指起手位置,用于区分点击与拖动。
var _pointer_start: Vector2 = Vector2.ZERO
# 本次按下是否已越过点击阈值(越过则松手不再算点击)。
var _pointer_dragged: bool = false
# 双指手势上一帧的间距/夹角,用于增量缩放与旋转。
var _pinch_distance: float = 0.0
var _pinch_angle: float = 0.0

# Viewing axis tracking
var _visible_cells: Dictionary = {}       # current frame's visible cells (for external queries)
var _prev_visible_cells: Dictionary = {}
var _initialized: bool = false

signal viewing_axis_changed(new_axis: Dictionary[Vector2i, bool], old_axis: Dictionary[Vector2i, bool])
# 点击世界(未拖动的单指触摸 / 鼠标左键):由 LevelActor 转发给当前 Mode。
signal tapped(screen_position: Vector2)

func _ready():
	target_position = global_position
	target_yaw = rotation.y
	yaw = rotation.y

func _input(in_event: InputEvent):
	if in_event is InputEventMouseButton:
		if in_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_input += 1
		elif in_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_input -= 1

# 世界手势:只处理真实触摸/鼠标事件,忽略系统模拟事件 —— 否则触屏上会同时收到
# "真实 touch" 与 "touch→mouse 模拟"、桌面会同时收到 "真实 mouse" 与
# "mouse→touch 模拟",同一手势被处理两次。
# 落在 UI 上的事件已由 GUI 消费,不会到达这里(故天然排除面板/按钮)。
func _unhandled_input(in_event: InputEvent):
	if in_event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if in_event is InputEventScreenTouch:
		_on_pointer(in_event.index, in_event.position, in_event.pressed)
	elif in_event is InputEventScreenDrag:
		_on_pointer_move(in_event.index, in_event.position)
	elif in_event is InputEventMouseButton:
		if in_event.button_index == MOUSE_BUTTON_LEFT:
			_on_pointer(_MOUSE_POINTER, in_event.position, in_event.pressed)
	elif in_event is InputEventMouseMotion:
		if in_event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_on_pointer_move(_MOUSE_POINTER, in_event.position)

func _process(in_delta: float):
	var movement_input = _get_movement_input()
	var rotation_input = _get_rotation_input()
	_handle_movement(movement_input, in_delta)
	_handle_rotation(rotation_input, in_delta)
	_handle_zoom(in_delta)
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

func _handle_movement(in_input_vector: Vector3, in_delta: float):
	if not smooth_movement and in_input_vector.length_squared() == 0:
		return
	var movement = in_input_vector * move_speed * in_delta
	if smooth_movement:
		target_position += movement
		global_position = global_position.lerp(target_position, smooth_factor)
	else:
		global_position += movement

func _handle_rotation(in_rotation_input: float, in_delta: float):
	if not smooth_movement and in_rotation_input == 0:
		return
	var rotation_amount = in_rotation_input * rotation_speed * in_delta
	if smooth_movement:
		target_yaw += rotation_amount
		yaw = lerp(yaw, target_yaw, smooth_factor)
		rotation.y = yaw
	else:
		rotate_y(rotation_amount)

func _handle_zoom(in_delta: float):
	if zoom_input == 0:
		return
	var zoom_vector = -global_transform.basis.z * zoom_input * zoom_speed * in_delta
	if smooth_movement:
		target_position += zoom_vector
	else:
		global_position += zoom_vector
	zoom_input = 0.0

# -------------------------------------------------------------------------- #
# Touch / mouse gestures
# -------------------------------------------------------------------------- #

func _on_pointer(in_index: int, in_position: Vector2, in_pressed: bool):
	if in_pressed:
		if _pointers.is_empty():
			_pointer_start = in_position
			_pointer_dragged = false
		_pointers[in_index] = in_position
		if _pointers.size() == 2:
			# 第二指落下即进入捏合/旋转手势,松手不再触发点击。
			_pointer_dragged = true
			_begin_two_finger()
		return
	_pointers.erase(in_index)
	if _pointers.is_empty():
		if not _pointer_dragged:
			tapped.emit(in_position)
		_pointer_dragged = false
		_pinch_distance = 0.0
		_pinch_angle = 0.0
	elif _pointers.size() == 1:
		# 双指抬起一根:以剩余指重新起锚,避免单指平移跳变。
		_pointer_start = _pointers.values()[0]
		_pinch_distance = 0.0
		_pinch_angle = 0.0

func _on_pointer_move(in_index: int, in_position: Vector2):
	if not _pointers.has(in_index):
		return
	var previous: Vector2 = _pointers[in_index]
	_pointers[in_index] = in_position
	if _pointers.size() == 1:
		if (in_position - _pointer_start).length() > tap_max_distance:
			_pointer_dragged = true
		if _pointer_dragged:
			_pan(previous, in_position)
	elif _pointers.size() == 2:
		_update_two_finger()

# 单指拖动:让 y=0 地面跟随手指(相机朝反方向平移),手感同"抓住地图拖动"。
func _pan(in_previous: Vector2, in_current: Vector2):
	var previous_ground := ground_point_from_screen(in_previous)
	var current_ground := ground_point_from_screen(in_current)
	if not previous_ground.is_finite() or not current_ground.is_finite():
		return
	var world_delta: Vector3 = previous_ground - current_ground
	target_position += world_delta
	if not smooth_movement:
		global_position += world_delta

func _begin_two_finger():
	var points: Array = _pointers.values()
	var a: Vector2 = points[0]
	var b: Vector2 = points[1]
	_pinch_distance = a.distance_to(b)
	_pinch_angle = (b - a).angle()

# 双指:间距变化 → 沿视线缩放;夹角变化 → 偏航旋转。
func _update_two_finger():
	var points: Array = _pointers.values()
	var a: Vector2 = points[0]
	var b: Vector2 = points[1]
	var distance: float = a.distance_to(b)
	var angle: float = (b - a).angle()
	if _pinch_distance > 0.0:
		var zoom_delta: float = distance - _pinch_distance
		var zoom_vector: Vector3 = -global_transform.basis.z * zoom_delta * pinch_zoom_speed
		target_position += zoom_vector
		if not smooth_movement:
			global_position += zoom_vector
	var angle_delta: float = wrapf(angle - _pinch_angle, -PI, PI)
	if not is_zero_approx(angle_delta):
		target_yaw -= angle_delta * twist_rotate_speed
		if not smooth_movement:
			rotation.y = target_yaw
	_pinch_distance = distance
	_pinch_angle = angle

# 视口坐标 → y=0 地面点;射线与地面平行/朝上或交点在相机背后时返回 Vector3.INF。
func ground_point_from_screen(in_screen_position: Vector2) -> Vector3:
	var origin: Vector3 = project_ray_origin(in_screen_position)
	var direction: Vector3 = project_ray_normal(in_screen_position)
	if is_zero_approx(direction.y):
		return Vector3.INF
	var t: float = -origin.y / direction.y
	if t < 0.0:
		return Vector3.INF
	return origin + direction * t

# -------------------------------------------------------------------------- #
# Viewing Axis — determines which grid cells (cell size=1 on y=0 plane) are
# visible from the camera, and emits changes each frame via _process().
# -------------------------------------------------------------------------- #
func _update_viewing_axis():
	var current_visible := _get_visible_cells()
	_visible_cells = current_visible

	if not _initialized:
		_prev_visible_cells = current_visible
		_initialized = true
		return

	var new_cells: Dictionary = {}
	var removed_cells: Dictionary = {}

	for cell: Vector2i in current_visible:
		if not _prev_visible_cells.has(cell):
			new_cells[cell] = true

	for cell: Vector2i in _prev_visible_cells:
		if not current_visible.has(cell):
			removed_cells[cell] = true

	if not new_cells.is_empty() or not removed_cells.is_empty():
		viewing_axis_changed.emit(new_cells, removed_cells)

	_prev_visible_cells = current_visible


# Public query — lets external code (e.g. map_actor._on_cells_changed) skip
# cells that are outside the current camera frustum.
func is_axis_visible(in_axis: Vector2i) -> bool:
	if _visible_cells.is_empty():
		_visible_cells = _get_visible_cells()
	return _visible_cells.has(in_axis)

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
static func _cell_intersects_ground(in_cx: float, in_cz: float, in_verts: Array[Vector2]) -> bool:
	var n := in_verts.size()
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
		var a := in_verts[i]
		var b := in_verts[(i + 1) % n]
		var edge := b - a
		axes.append(Vector2(-edge.y, edge.x).normalized())

	for axis in axes:
		var nx := axis.x
		var ny := axis.y
		# Project cell (half-size = 0.5)
		var cell_center_p: float = in_cx * nx + in_cz * ny
		var cell_min: float = cell_center_p - 0.5 * (abs(nx) + abs(ny))
		var cell_max: float = cell_center_p + 0.5 * (abs(nx) + abs(ny))
		# Project polygon
		var poly_min :=  INF
		var poly_max := -INF
		for v in in_verts:
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
	in_cx: float, in_cz: float,
	in_ground_verts: Array[Vector2],
	in_cam_pos: Vector3, in_cam_dir: Vector3, in_far_dist: float,
) -> bool:
	# First check whether the cell as a whole intersects the ground polygon
	if not _cell_intersects_ground(in_cx, in_cz, in_ground_verts):
		return false

	# Now check far-plane: at least one corner must be within far distance
	var corners := [
		Vector2(in_cx - 0.5, in_cz - 0.5),
		Vector2(in_cx + 0.5, in_cz - 0.5),
		Vector2(in_cx - 0.5, in_cz + 0.5),
		Vector2(in_cx + 0.5, in_cz + 0.5),
	]
	for p in corners:
		var to_cell := Vector3(p.x, 0.0, p.y) - in_cam_pos
		if to_cell.dot(in_cam_dir) <= in_far_dist:
			return true
	# All corners are beyond far plane → treat as invisible
	return false
