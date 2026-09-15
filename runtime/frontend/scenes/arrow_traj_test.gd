extends Node3D

# 弩矢弹道调试场景(开发工具,不参与正式流程):
#   拖动"目标距离"滑块 → 移动靶子,实时观察弩身俯仰 / 箭离弦仰角;
#   拖动"重力 G"滑块   → 直接改 Trajectory.GRAVITY,实时看抛物线弧度变化;
#   拖动"俯仰转轴 P / 起点偏移"滑块 → 直接改 Crossbow 的射箭几何(转轴 + 起点偏移)。
# 数据流走真实链路:BuildingActor 每帧读 crossbow.target.position → TurretModel.set_target_position
# → Trajectory.aim_pitch_for,所以 HUD 数字就是模型实际采用的值,不是另算一份。
#
# 俯仰几何(生产代码 Crossbow 里已落库,本场景只是可视化 + 试参):
#   转轴 P = O + forward·PIVOT_FORWARD + up·PIVOT_HEIGHT      (O=弩中心地面点)
#   起点 S = P + R(θ)·(SPAWN_FORWARD, SPAWN_HEIGHT)          (弩身局部系,随俯仰角 θ 旋转)
#   射箭起点高度 = S.y —— 不再固定,随俯仰变化。
# 标记颜色:青=转轴 P,绿=几何起点 S,品红=模型弦上箭实际位置(对齐参考)。
# 相机:滚轮缩放 / 右键拖拽平移 / 中键拖拽环绕;拖动"目标距离"不移动相机(需要时点"重置视角")。

# —— 场景布局 ——
# 弩炮所在格(后端地面网格坐标)。靶子沿 +Z 拉开(与 crossbow_test 同向,规避炮塔 yaw 换算歧义)。
const CROSSBOW_AXIS: Vector2i = Vector2i(3, 3)
const AIM_AXIS: Vector2 = Vector2(0.0, 1.0)

# —— 滑块量程 ——
const DIST_MIN: float = 1.0
const DIST_MAX: float = 16.0
const DIST_DEFAULT: float = 4.0
const GRAVITY_MIN: float = 2.0
const GRAVITY_MAX: float = 40.0
const GRAVITY_STEP: float = 0.5
const GRAVITY_DEFAULT: float = 9.8

# 俯仰转轴 P 与起点偏移的默认值(= 生产代码 Crossbow 的落库值;启动时回写一遍便于试参)。
const PIVOT_FORWARD_MIN: float = -0.5
const PIVOT_FORWARD_MAX: float = 1.5
const PIVOT_FORWARD_DEFAULT: float = 0.16
const PIVOT_HEIGHT_MIN: float = 0.0
const PIVOT_HEIGHT_MAX: float = 2.0
const PIVOT_HEIGHT_DEFAULT: float = 0.62
const SPAWN_FORWARD_MIN: float = -0.5
const SPAWN_FORWARD_MAX: float = 1.5
const SPAWN_FORWARD_DEFAULT: float = 0.44
const SPAWN_HEIGHT_MIN: float = -0.6
const SPAWN_HEIGHT_MAX: float = 0.6
const SPAWN_HEIGHT_DEFAULT: float = 0.09

# 滚轮缩放:相机取景距离倍率
const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 4.0
const ZOOM_STEP: float = 1.15
# 右键拖拽平移 / 中键拖拽环绕(速率)
const PAN_SPEED: float = 0.0018
const ORBIT_SPEED: float = 0.008

# 预测折线采样段数
const TRAJ_SEGMENTS: int = 48

var _level: Level = null
var _crossbow: Crossbow = null
var _target: Enemy = null
var _actor: BuildingActor = null
var _target_actor: EntityActor = null
var _camera: Camera3D = null
var _traj_mesh: MeshInstance3D = null
var _traj_im: ImmediateMesh = null

var _distance: float = DIST_DEFAULT
var _zoom: float = 1.0
var _pan: Vector3 = Vector3.ZERO
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = 0.0
var _panning: bool = false
var _orbiting: bool = false
# 相机基准取景(不随"目标距离"变化;仅"重置视角"时按当前距离重算)
var _cam_base_mid: Vector3 = Vector3.ZERO
var _cam_base_offset: Vector3 = Vector3.ZERO
var _hud: Label = null
var _dist_value_label: Label = null
var _grav_value_label: Label = null

# 俯仰几何可视化标记/标签(几何数值本体在 Crossbow 的静态字段)
var _pivot_value_label: Label = null
var _spawn_value_label: Label = null
var _pivot_marker: MeshInstance3D = null
var _spawn_marker: MeshInstance3D = null
var _arrow_ref_marker: MeshInstance3D = null
var _geom_im: ImmediateMesh = null

func _ready():
	# 复位可调试常量,避免上一次运行残留(static var 在同一进程内会保留)。
	Trajectory.GRAVITY = GRAVITY_DEFAULT
	Crossbow.PIVOT_FORWARD = PIVOT_FORWARD_DEFAULT
	Crossbow.PIVOT_HEIGHT = PIVOT_HEIGHT_DEFAULT
	Crossbow.SPAWN_FORWARD = SPAWN_FORWARD_DEFAULT
	Crossbow.SPAWN_HEIGHT = SPAWN_HEIGHT_DEFAULT
	_build_backend()
	_build_frontend()
	_set_distance(DIST_DEFAULT)

func _process(_delta: float):
	# 弩身俯仰由 BuildingActor._process 每帧据 target 刷新;这里刷新几何标记/读数。
	_force_show_arrow()
	_update_geometry()
	_update_trajectory()
	_update_hud()

# 相机:滚轮缩放 / 右键拖拽平移 / 中键拖拽环绕(不影响滑块拖拽;面板上滚轮也生效)。
func _input(in_event: InputEvent):
	var mb := in_event as InputEventMouseButton
	if mb:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom = clampf(_zoom / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom = clampf(_zoom * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
					_update_camera()
			MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_orbiting = mb.pressed
		return
	var mm := in_event as InputEventMouseMotion
	if mm:
		if _panning:
			_pan_camera(mm.relative)
		elif _orbiting:
			_orbit_camera(mm.relative)

# 右键平移:把视点沿相机屏幕平面拖动(拖动方向跟手)
func _pan_camera(in_relative: Vector2):
	var right: Vector3 = _camera.global_transform.basis.x
	var up: Vector3 = _camera.global_transform.basis.y
	var radius: float = _cam_base_offset.length() * _zoom
	_pan += (-right * in_relative.x + up * in_relative.y) * PAN_SPEED * radius
	_update_camera()

# 中键环绕:左右改偏航,上下改俯仰
func _orbit_camera(in_relative: Vector2):
	_orbit_yaw -= in_relative.x * ORBIT_SPEED
	_orbit_pitch = clampf(_orbit_pitch - in_relative.y * ORBIT_SPEED, -1.2, 1.2)
	_update_camera()

# ---------------------------------------------------------------- #
# backend:最小可运行 Level(只放弩与靶,不 tick 玩法)
# ---------------------------------------------------------------- #
func _build_backend():
	_level = Level.new()
	add_child(_level)
	Level.current = _level

	# 24×24 全 dirt,足够覆盖最大射程
	var map_data := MapData.new()
	map_data.size = Vector2i(24, 24)
	map_data.cells = []
	for r in range(24):
		var row := CellRowData.new()
		row.cells = []
		for c in range(24):
			var cell := CellData.new()
			var land := LandData.new()
			land.type = "dirt"
			cell.land = land
			row.cells.append(cell)
		map_data.cells.append(row)
	_level.map.load_data(map_data)

	# 弩:朝 +Z(与靶同轴),炮塔瞄准也指向 +Z
	var bd := BuildingData.new()
	bd.type = "crossbow"
	bd.direction = Vector2i.UP
	_crossbow = _level.map.place_building(CROSSBOW_AXIS, bd, true) as Crossbow
	_crossbow.input_bag.add_count(1)
	_crossbow.aim_direction = AIM_AXIS

	# 靶:静止敌人(Slime extends Enemy,且有前端模型),位置由距离滑块驱动
	_target = Entity.create("slime") as Enemy
	_target.move_speed = 0.0
	_target.position = _target_position(_distance)
	_level.room.add_entity(_target)
	# 让 BuildingActor 每帧据 target.position 更新弩身俯仰
	_crossbow.target = _target

func _target_position(in_distance: float) -> Vector2:
	return Vector2(CROSSBOW_AXIS) + AIM_AXIS * in_distance

# ---------------------------------------------------------------- #
# frontend:相机 / 灯光 / actor / 预测折线 / 几何标记 / UI
# ---------------------------------------------------------------- #
func _build_frontend():
	_build_lights()
	_build_ground()

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.current = true
	_camera.fov = 45.0
	add_child(_camera)

	# 弩 actor(真实链路:信号驱动模型状态/朝向)
	var actor_tscn: PackedScene = preload("res://runtime/frontend/actors/building_actor.tscn")
	_actor = actor_tscn.instantiate() as BuildingActor
	_actor.name = "crossbow_actor"
	add_child(_actor)
	_actor.bind(_crossbow)
	# 停在"射出前一刻"(满弦待发):非 idle → 弦上箭显示;progress=1 → 箭落在满弦位(即射箭起点)。
	# 必须放在 bind 之后,确保 stored_count 已同步(_loaded_count>0),箭才会显示并被定位。
	_crossbow.state = "ready"
	_crossbow.progress = 1.0

	# 靶 actor
	var ea_tscn: PackedScene = preload("res://runtime/frontend/actors/entity_actor.tscn")
	_target_actor = ea_tscn.instantiate() as EntityActor
	_target_actor.name = "target_actor"
	add_child(_target_actor)
	_target_actor.bind(_target)

	# 预测弹道折线
	_traj_im = ImmediateMesh.new()
	_traj_mesh = MeshInstance3D.new()
	_traj_mesh.name = "trajectory"
	_traj_mesh.mesh = _traj_im
	var traj_mat := StandardMaterial3D.new()
	traj_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	traj_mat.albedo_color = Color(1.0, 0.85, 0.2)
	_traj_mesh.material_override = traj_mat
	add_child(_traj_mesh)

	_build_geometry_markers()
	_build_ui()
	_frame_camera_to_distance()

# 俯仰几何可视化:转轴/起点/弦上箭参考 三个小球 + 转轴线/弩身线/落线。
func _build_geometry_markers():
	_geom_im = ImmediateMesh.new()
	var geom := MeshInstance3D.new()
	geom.name = "pitch_geometry"
	geom.mesh = _geom_im
	var geom_mat := StandardMaterial3D.new()
	geom_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	geom_mat.albedo_color = Color(0.2, 1.0, 0.9)
	geom_mat.no_depth_test = true
	geom.material_override = geom_mat
	add_child(geom)

	_pivot_marker = _make_marker(Color(0.2, 0.9, 1.0), 0.05)
	_pivot_marker.name = "pivot_marker"
	add_child(_pivot_marker)
	_spawn_marker = _make_marker(Color(0.3, 1.0, 0.3), 0.05)
	_spawn_marker.name = "spawn_marker"
	add_child(_spawn_marker)
	_arrow_ref_marker = _make_marker(Color(1.0, 0.3, 1.0), 0.035)
	_arrow_ref_marker.name = "arrow_ref_marker"
	add_child(_arrow_ref_marker)

func _make_marker(in_color: Color, in_radius: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = in_radius
	sphere.height = in_radius * 2.0
	m.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = in_color
	mat.no_depth_test = true
	m.material_override = mat
	return m

func _build_lights():
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	light.light_energy = 1.6
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-25), deg_to_rad(140), 0)
	fill.light_energy = 0.6
	add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.35, 0.40)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

# 地面 + 沿 +Z 每 1 格的横向标尺线 + 每 2 格一个距离 Label3D,便于目测射程。
func _build_ground():
	var plane := PlaneMesh.new()
	plane.size = Vector2(48, 48)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.position = Vector3(CROSSBOW_AXIS.x, 0, CROSSBOW_AXIS.y + 8)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.22, 0.24, 0.20)
	ground.material_override = ground_mat
	add_child(ground)

	var half_w: float = 4.0
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for d in range(0, int(DIST_MAX) + 3):
		var z: float = float(CROSSBOW_AXIS.y + d)
		im.surface_add_vertex(Vector3(CROSSBOW_AXIS.x - half_w, 0.01, z))
		im.surface_add_vertex(Vector3(CROSSBOW_AXIS.x + half_w, 0.01, z))
	im.surface_end()
	var lines := MeshInstance3D.new()
	lines.mesh = im
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = Color(1, 1, 1, 0.22)
	lines.material_override = line_mat
	add_child(lines)

	for d in range(2, int(DIST_MAX) + 1, 2):
		var lbl := Label3D.new()
		lbl.text = "%d" % d
		lbl.font_size = 48
		lbl.pixel_size = 0.006
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = Color(0.92, 0.92, 0.92)
		lbl.position = Vector3(CROSSBOW_AXIS.x - half_w - 0.6, 0.12, CROSSBOW_AXIS.y + d)
		add_child(lbl)

func _build_ui():
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "弩矢弹道调试"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	# 调距离不动相机;需要重新取景时点这里(按当前距离重置缩放/平移/环绕)
	var reset_btn := Button.new()
	reset_btn.text = "重置视角(按当前距离取景)"
	reset_btn.pressed.connect(_frame_camera_to_distance)
	vbox.add_child(reset_btn)

	# 目标距离
	_dist_value_label = Label.new()
	_dist_value_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_dist_value_label)
	var dist_slider := HSlider.new()
	dist_slider.min_value = DIST_MIN
	dist_slider.max_value = DIST_MAX
	dist_slider.step = 0.1
	dist_slider.value = DIST_DEFAULT
	dist_slider.custom_minimum_size = Vector2(380, 0)
	dist_slider.value_changed.connect(_on_distance_changed)
	vbox.add_child(dist_slider)

	# 重力
	_grav_value_label = Label.new()
	_grav_value_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_grav_value_label)
	var grav_slider := HSlider.new()
	grav_slider.min_value = GRAVITY_MIN
	grav_slider.max_value = GRAVITY_MAX
	grav_slider.step = GRAVITY_STEP
	grav_slider.value = Trajectory.GRAVITY
	grav_slider.custom_minimum_size = Vector2(380, 0)
	grav_slider.value_changed.connect(_on_gravity_changed)
	vbox.add_child(grav_slider)

	# 俯仰转轴 P:forward
	_pivot_value_label = Label.new()
	_pivot_value_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_pivot_value_label)
	var pf_slider := HSlider.new()
	pf_slider.min_value = PIVOT_FORWARD_MIN
	pf_slider.max_value = PIVOT_FORWARD_MAX
	pf_slider.step = 0.01
	pf_slider.value = Crossbow.PIVOT_FORWARD
	pf_slider.custom_minimum_size = Vector2(380, 0)
	pf_slider.value_changed.connect(_on_pivot_forward_changed)
	vbox.add_child(pf_slider)
	var ph_slider := HSlider.new()
	ph_slider.min_value = PIVOT_HEIGHT_MIN
	ph_slider.max_value = PIVOT_HEIGHT_MAX
	ph_slider.step = 0.01
	ph_slider.value = Crossbow.PIVOT_HEIGHT
	ph_slider.custom_minimum_size = Vector2(380, 0)
	ph_slider.value_changed.connect(_on_pivot_height_changed)
	vbox.add_child(ph_slider)

	# 射箭起点偏移(相对转轴)
	_spawn_value_label = Label.new()
	_spawn_value_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_spawn_value_label)
	var sf_slider := HSlider.new()
	sf_slider.min_value = SPAWN_FORWARD_MIN
	sf_slider.max_value = SPAWN_FORWARD_MAX
	sf_slider.step = 0.01
	sf_slider.value = Crossbow.SPAWN_FORWARD
	sf_slider.custom_minimum_size = Vector2(380, 0)
	sf_slider.value_changed.connect(_on_spawn_forward_changed)
	vbox.add_child(sf_slider)
	var sh_slider := HSlider.new()
	sh_slider.min_value = SPAWN_HEIGHT_MIN
	sh_slider.max_value = SPAWN_HEIGHT_MAX
	sh_slider.step = 0.01
	sh_slider.value = Crossbow.SPAWN_HEIGHT
	sh_slider.custom_minimum_size = Vector2(380, 0)
	sh_slider.value_changed.connect(_on_spawn_height_changed)
	vbox.add_child(sh_slider)

	# 读数
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_hud)

	_update_dist_label()
	_update_grav_label()
	_update_pivot_label()
	_update_spawn_label()

# ---------------------------------------------------------------- #
# 交互
# ---------------------------------------------------------------- #
func _on_distance_changed(in_value: float):
	_set_distance(in_value)

func _on_gravity_changed(in_value: float):
	Trajectory.GRAVITY = in_value
	_update_grav_label()

func _on_pivot_forward_changed(in_value: float):
	Crossbow.PIVOT_FORWARD = in_value
	_update_pivot_label()

func _on_pivot_height_changed(in_value: float):
	Crossbow.PIVOT_HEIGHT = in_value
	_update_pivot_label()

func _on_spawn_forward_changed(in_value: float):
	Crossbow.SPAWN_FORWARD = in_value
	_update_spawn_label()

func _on_spawn_height_changed(in_value: float):
	Crossbow.SPAWN_HEIGHT = in_value
	_update_spawn_label()

func _update_pivot_label():
	if _pivot_value_label:
		_pivot_value_label.text = "俯仰转轴 P: forward %.2f  height %.2f" % [Crossbow.PIVOT_FORWARD, Crossbow.PIVOT_HEIGHT]

func _update_spawn_label():
	if _spawn_value_label:
		_spawn_value_label.text = "起点偏移(相对 P): forward %.2f  up %.2f" % [Crossbow.SPAWN_FORWARD, Crossbow.SPAWN_HEIGHT]

func _set_distance(in_distance: float):
	_distance = in_distance
	if _target:
		_target.position = _target_position(_distance)
	_update_dist_label()
	# 不调用 _update_camera():调距离时相机保持不动(需要重新取景时点"重置视角")。

func _update_dist_label():
	if _dist_value_label:
		_dist_value_label.text = "目标距离(格,弩心→靶): %.2f" % _distance

func _update_grav_label():
	if _grav_value_label:
		_grav_value_label.text = "重力 G(世界单位/s²): %.1f" % Trajectory.GRAVITY

# ---------------------------------------------------------------- #
# 俯仰几何:转轴 P、起点 S(随俯仰旋转)
# ---------------------------------------------------------------- #

# 当前离弦仰角 θ(与 backend fire() 完全同源:Trajectory.aim_pitch_for)。
func _pitch_angle() -> float:
	return Trajectory.aim_pitch_for(Vector2(CROSSBOW_AXIS), AIM_AXIS, _target.position, Vector2(Crossbow.PIVOT_FORWARD, Crossbow.PIVOT_HEIGHT), Vector2(Crossbow.SPAWN_FORWARD, Crossbow.SPAWN_HEIGHT), Crossbow.ARROW_SPEED)

func _forward_axis() -> Vector3:
	return Vector3(AIM_AXIS.x, 0.0, AIM_AXIS.y)

# 转轴 P = O + forward·PIVOT_FORWARD + up·PIVOT_HEIGHT
func _pivot_world() -> Vector3:
	var o := Vector3(CROSSBOW_AXIS.x, 0.0, CROSSBOW_AXIS.y)
	return o + _forward_axis() * Crossbow.PIVOT_FORWARD + Vector3.UP * Crossbow.PIVOT_HEIGHT

# 起点 S = O + forward·off.x + up·off.y,off = Trajectory.spawn_offset_at(θ, P, S)
func _spawn_world() -> Vector3:
	var o := Vector3(CROSSBOW_AXIS.x, 0.0, CROSSBOW_AXIS.y)
	var off: Vector2 = Trajectory.spawn_offset_at(_pitch_angle(), Vector2(Crossbow.PIVOT_FORWARD, Crossbow.PIVOT_HEIGHT), Vector2(Crossbow.SPAWN_FORWARD, Crossbow.SPAWN_HEIGHT))
	return o + _forward_axis() * off.x + Vector3.UP * off.y

func _update_geometry():
	if not _pivot_marker or not _spawn_marker or not _geom_im:
		return
	var pivot: Vector3 = _pivot_world()
	var spawn: Vector3 = _spawn_world()
	_pivot_marker.position = pivot
	_spawn_marker.position = spawn

	# 弦上箭实际世界位置(对齐参考;正式流程 idle 时隐藏,这里强制显示)
	var ref: Vector3 = Vector3.ZERO
	var has_ref: bool = false
	if _actor and _actor.building_model:
		var a: Node3D = _actor.building_model.get_node_or_null("%Arrow")
		if a:
			ref = a.global_position
			has_ref = true
	_arrow_ref_marker.visible = has_ref
	if has_ref:
		_arrow_ref_marker.position = ref

	# 线:转轴(过 P 沿世界 X 的短线)+ 弩身(P→S 延长)+ 落线(S→地面)
	var dir: Vector3 = spawn - pivot
	if dir.length() < 0.0001:
		dir = Vector3.UP
	dir = dir.normalized()
	_geom_im.clear_surfaces()
	_geom_im.surface_begin(Mesh.PRIMITIVE_LINES)
	var half: float = 0.45
	_geom_im.surface_add_vertex(pivot + Vector3(-half, 0, 0))
	_geom_im.surface_add_vertex(pivot + Vector3(half, 0, 0))
	_geom_im.surface_add_vertex(pivot - dir * 0.25)
	_geom_im.surface_add_vertex(spawn + dir * 0.25)
	_geom_im.surface_add_vertex(spawn)
	_geom_im.surface_add_vertex(Vector3(spawn.x, 0.0, spawn.z))
	_geom_im.surface_end()

# ---------------------------------------------------------------- #
# 表现刷新
# ---------------------------------------------------------------- #

# 强制显示弦上箭,便于肉眼对比它和预测折线的离弦方向(正式流程里 idle 时它是隐藏的)。
func _force_show_arrow():
	if not _actor or not _actor.building_model:
		return
	var a: Node3D = _actor.building_model.get_node_or_null("%Arrow")
	if a:
		a.visible = true

# 预测弹道:起点=几何起点 S(高度随俯仰变化),与 Trajectory 同公式 y(t)=h·(1-t)+A·t·(1-t)。
func _update_trajectory():
	if not _traj_im or not _target:
		return
	var start: Vector3 = _spawn_world()
	var h: float = start.y
	var v: float = Crossbow.ARROW_SPEED
	var end: Vector3 = Vector3(_target.position.x, 0, _target.position.y)
	var d: float = Vector2(start.x, start.z).distance_to(Vector2(end.x, end.z))
	var t: float = d / v if v > 0.0 else 0.0
	var arc: float = 0.5 * Trajectory.GRAVITY * t * t

	_traj_im.clear_surfaces()
	_traj_im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(TRAJ_SEGMENTS + 1):
		var f: float = float(i) / float(TRAJ_SEGMENTS)
		var p: Vector3 = start.lerp(end, f)
		p.y = h * (1.0 - f) + arc * f * (1.0 - f)
		_traj_im.surface_add_vertex(p)
	_traj_im.surface_end()

# 按当前目标距离重算相机基准取景并立即应用(只在启动与"重置视角"时调用;
# 拖动"目标距离"滑块本身不改相机,避免目标一动镜头就跟着飘)。
func _frame_camera_to_distance():
	_cam_base_mid = Vector3(CROSSBOW_AXIS.x, 0.9, CROSSBOW_AXIS.y + _distance * 0.5)
	_cam_base_offset = Vector3(9.0 + _distance * 0.8, 3.2 + _distance * 0.14, 0.0)
	_update_camera()

# 相机侧视:基准从 +X 看 YZ 平面,叠加缩放/平移/环绕。基准不依赖"目标距离"。
func _update_camera():
	if not _camera:
		return
	var mid: Vector3 = _cam_base_mid + _pan
	var radius: float = _cam_base_offset.length() * _zoom
	var base_dir: Vector3 = _cam_base_offset.normalized()
	var horiz: Vector3 = Vector3(base_dir.x, 0.0, base_dir.z)
	if horiz.length() < 0.0001:
		horiz = Vector3.RIGHT
	horiz = horiz.normalized().rotated(Vector3.UP, _orbit_yaw)
	var pitch: float = clampf(asin(base_dir.y) + _orbit_pitch, -1.3, 1.3)
	var dir: Vector3 = Vector3(horiz.x * cos(pitch), sin(pitch), horiz.z * cos(pitch))
	_camera.position = mid + dir * radius
	_camera.look_at(mid, Vector3.UP)

# 弦上箭朝向仰角(箭 +Z 指向目标):用于核验弩身/箭的俯仰是否与弹道一致。
func _measure_barrel_elevation(in_model: Node3D) -> float:
	var arrow: Node3D = in_model.get_node_or_null("%Arrow")
	if not arrow:
		return 0.0
	var fwd: Vector3 = arrow.global_transform.basis.z.normalized()
	return rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))

func _update_hud():
	if not _crossbow:
		return
	var v: float = Crossbow.ARROW_SPEED
	var g: float = Trajectory.GRAVITY
	var spawn: Vector3 = _spawn_world()
	var h: float = spawn.y
	var d: float = Vector2(spawn.x, spawn.z).distance_to(_target.position)
	var t: float = d / v if v > 0.0 else 0.0
	var arc: float = 0.5 * g * t * t
	var pitch: float = rad_to_deg(_pitch_angle())
	var apex_t: float = 0.0
	if arc > h:
		apex_t = (1.0 - h / arc) / 2.0
	var apex_y: float = h * (1.0 - apex_t) + arc * apex_t * (1.0 - apex_t)

	var barrel_rot: float = 0.0
	var measured: float = 0.0
	if _actor and _actor.building_model:
		var body: Node3D = _actor.building_model.get_node_or_null("%body")
		if body:
			barrel_rot = rad_to_deg(body.rotation.x)
		measured = _measure_barrel_elevation(_actor.building_model)

	_hud.text = (
		"箭离弦仰角 θ = %+.2f°   (弹道切线)\n" % pitch
		+ "起点 S:forward %.2f  height %.3f 格\n" % [spawn.z - CROSSBOW_AXIS.y, h]
		+ "起点→靶水平距离 = %.2f 格   飞行 T = %.3f s\n" % [d, t]
		+ "拱高 A/4 = %.3f   弧顶 %.3f 格 @ t=%.2f\n" % [arc / 4.0, apex_y, apex_t]
		+ "弩身 rotation.x = %+.2f°   弦上箭仰角 = %+.2f°\n" % [barrel_rot, measured]
		+ "重力 G = %.1f" % g
	)
