class_name InspectMode
extends Mode

# 建筑检视模式:面板打开期间接管输入 —— ESC 关闭回 roaming;点另一建筑则切换选中并刷新面板
# (无需先关面板);点击落在面板 UI 上时不触发切换(避免误选)。
# 面板关闭来自三条路径:① ESC → owner.close_inspector();② 面板内 × 按钮 →
# BuildingInspectorHost._on_child_closed → owner.close_inspector();③ 点另一建筑切换。
# 全部汇聚到 LevelActor.inspect_building/close_inspector,故本类不负责 leave 清理。

func tick(_in_delta: float):
	if Input.is_key_pressed(KEY_ESCAPE):
		owner.close_inspector()
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	if _is_pointer_over_panel():
		return
	var axis = get_pointing_axis()
	if axis == null:
		return
	var map: Map = Level.current.map
	var cell: Cell = map.get_cell(axis)
	# 点空白处(无建筑格):关闭检视面板并清选中,回 roaming。
	if not cell or not cell.building:
		owner.close_inspector()
		return
	# 点到了另一建筑:重新选中并刷新面板(切换);点到当前选中建筑则保持
	if cell.building != owner.selected_building:
		owner.inspect_building(cell.building)

# 点击是否落在检视面板矩形内(屏幕空间);是则忽略,让面板自身处理。
func _is_pointer_over_panel() -> bool:
	var panel: Control = owner.get_node_or_null("%inspector/Panel") as Control
	if not panel:
		return false
	var mouse: Vector2 = get_viewport().get_mouse_position()
	# 遍历已显示的检视子面板(CrossbowPanel/WorkshopPanel),任一覆盖该点即视为落在面板上
	for child in panel.get_children():
		if child is Control and child.visible:
			var rect: Rect2 = (child as Control).get_global_rect()
			if rect.has_point(mouse):
				return true
	return false

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
