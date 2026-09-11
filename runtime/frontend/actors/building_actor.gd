extends Node3D
class_name BuildingActor

var building: Building = null
var type: String = ""
var building_model: Node3D = null
var axis: Vector2i = Vector2i.ZERO
var direction: Vector2i = Vector2i.UP

# —— 选中高亮 ——
# 选中状态由 frontend(LevelActor.selected_building)持有;本 actor 只是表现层:
# set_selected(true/false) 显隐选中地盘(SelectionRing),不接触 backend 玩法。
var selected: bool = false
var _selection_ring: Node3D = null

# —— 攻击范围显示 ——
# 选中攻击型建筑时,在其所在格铺一块半透明圆形范围面(半径取自 backend.get_attack_range())。
# 与 _selection_ring 同属表现层,由 set_selected 显隐;backend 不感知本节点。
var _range_indicator: Node3D = null

@onready var work_progress: HeadBarGroup = %work_progress

# 显隐选中高亮(点击选中建筑时由 LevelActor 驱动)。
func set_selected(in_selected: bool):
	if in_selected == selected:
		return
	selected = in_selected
	if not _selection_ring:
		_build_selection_ring()
	if _selection_ring:
		_selection_ring.visible = selected
	_update_range_indicator()

# 程序化生成选中地盘:一个略大于建筑基座、半透明发光的圆环,铺在 y=0 地面。
# 用 TorusMesh 环而非改模型材质(模型共享,污染大);中心镂空不遮模型,对任意建筑通用。
func _build_selection_ring():
	var ring := MeshInstance3D.new()
	ring.name = "SelectionRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.58
	ring_mesh.outer_radius = 0.72
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 32
	ring.mesh = ring_mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.25, 0.85, 1.0, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.85, 1.0)
	mat.emission_energy_multiplier = 1.5
	ring.material_override = mat
	# TorusMesh 默认已在 XZ 平面(绕 Y 轴的平躺环),直接平铺地面即可,勿再绕 X 旋转(会立起来)。
	# 略抬 y 防与地面 z-fight。
	ring.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0))
	ring.visible = false
	add_child(ring)
	_selection_ring = ring

# 范围面显隐:仅当选中且建筑有攻击范围(backend.get_attack_range() > 0)时显示。
# 非攻击建筑不构建、不显示;惰性构建,尺寸由 backend 值决定(单一事实来源)。
func _update_range_indicator():
	var range_half: float = 0.0
	if building:
		range_half = building.get_attack_range()
	if range_half <= 0.0:
		if _range_indicator:
			_range_indicator.visible = false
		return
	if not _range_indicator:
		_build_range_indicator(range_half)
	if _range_indicator:
		_range_indicator.visible = selected

# 程序化生成范围面:一个容器节点,内含半透明圆形填充(极扁圆柱,顶/底面即圆盘)
# 与半径处的环形边框。以建筑所在格为中心铺在 XZ 平面;略抬 y 防 z-fight,且低于选中环(y=0.03)。
# 建筑方向为 4 向(90° 倍数),look_at 旋转下圆形外观不变,无需额外对齐。
func _build_range_indicator(in_range_half: float):
	var indicator := Node3D.new()
	indicator.name = "AttackRangeIndicator"
	# 填充:极扁圆柱,top/bottom 半径 = in_range_half
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	var disk := CylinderMesh.new()
	disk.height = 0.01
	disk.top_radius = in_range_half
	disk.bottom_radius = in_range_half
	disk.radial_segments = 48
	disk.rings = 1
	fill.mesh = disk
	var fill_mat := StandardMaterial3D.new()
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.albedo_color = Color(1.0, 0.35, 0.25, 0.20)
	fill_mat.emission_enabled = true
	fill_mat.emission = Color(1.0, 0.35, 0.25)
	fill_mat.emission_energy_multiplier = 1.0
	fill_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill.material_override = fill_mat
	fill.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0))
	indicator.add_child(fill)
	# 边框:半径处一圈细环(TorusMesh 默认平躺 XZ),更实更亮,render_priority 保证盖在填充之上
	var border := MeshInstance3D.new()
	border.name = "Border"
	var ring := TorusMesh.new()
	var border_half_width: float = 0.05
	ring.inner_radius = in_range_half - border_half_width
	ring.outer_radius = in_range_half + border_half_width
	ring.rings = 96
	ring.ring_segments = 12
	border.mesh = ring
	var border_mat := StandardMaterial3D.new()
	border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_mat.albedo_color = Color(1.0, 0.45, 0.30, 0.9)
	border_mat.emission_enabled = true
	border_mat.emission = Color(1.0, 0.45, 0.30)
	border_mat.emission_energy_multiplier = 1.5
	border_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	border_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	border.material_override = border_mat
	border.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.025, 0))
	border_mat.render_priority = 1
	indicator.add_child(border)
	indicator.visible = false
	add_child(indicator)
	_range_indicator = indicator

func bind(in_building: Building):
	if building:
		building.state_changed.disconnect(_on_building_state_changed)
		building.progress_changed.disconnect(_on_building_progress_changed)
		if building.has_signal(&"aim_direction_changed"):
			building.aim_direction_changed.disconnect(_on_building_aim_direction_changed)
	building = in_building
	# 重绑(复用池回收/重建)时复位选中,避免上个建筑的高亮残留
	selected = false
	if _selection_ring:
		_selection_ring.visible = false
	if _range_indicator:
		_range_indicator.visible = false
	if not building:
		work_progress.bind_source(null)
		_bind_display_bag()
		return
	if building.type != type:
		type = building.type
		_on_type_changed()
	if building.axis != axis:
		axis = building.axis
		_on_axis_changed()
	if building.direction != direction:
		direction = building.direction
		_on_direction_changed()
	building.state_changed.connect(_on_building_state_changed)
	building.progress_changed.connect(_on_building_progress_changed)
	if building.has_signal(&"aim_direction_changed"):
		building.aim_direction_changed.connect(_on_building_aim_direction_changed)
	# 数据源经组统一下发给全部子条(容量条 + 工作量条),各自按 _value() 决定显隐
	work_progress.bind_source(building)
	_on_building_state_changed()
	_on_building_progress_changed()
	_on_building_aim_direction_changed()
	_bind_display_bag()
	_update_direction()

func get_type_key() -> String:
	return "Building_%s" % type

func _on_type_changed():
	if building_model:
		remove_child(building_model)
		building_model.queue_free()
	# 类型变化后攻击范围可能不同,销毁旧范围面,下次选中按新类型重建
	if _range_indicator:
		remove_child(_range_indicator)
		_range_indicator.queue_free()
		_range_indicator = null
	var building_path: String = "res://runtime/frontend/models/buildings/%s/%s.tscn" % [type, type]
	var building_scene: PackedScene = load(building_path)
	building_model = building_scene.instantiate()
	if building_model:
		add_child(building_model)
		building_model.owner = owner
		# 组统一定位/测量;容量条与工作量条均为其子条,随组竖排
		work_progress.setup(self, building_model)

func _on_axis_changed():
	position = Vector3(axis.x, 0, axis.y)

func _on_direction_changed():
	look_at(global_position + Vector3(direction.x, 0, direction.y))

func _process(_delta: float):
	_update_direction()
# 水平朝向:跟随 backend 的 aim_direction(信号驱动)
func _on_building_aim_direction_changed():
	if not building_model:
		return
	if not building_model.has_method(&"set_aim_direction"):
		return
	if not building or not building.has_signal(&"aim_direction_changed"):
		return
	var aim: Vector2 = building.aim_direction
	building_model.set_aim_direction(Vector3(aim.x, 0, aim.y))

# 俯仰:每帧按目标距离调整,无需信号
func _update_direction():
	if not building_model:
		return
	if not building_model.has_method(&"set_target_position"):
		return
	if not building:
		return
	if not building.target:
		return
	var target_position = building.target.position
	building_model.set_target_position(Vector3(target_position.x, 0, target_position.y))

func _on_building_state_changed():
	if not building:
		return
	if not building_model:
		return
	if not building_model.has_method(&"set_state"):
		return
	building_model.set_state(building.state)

func _on_building_progress_changed():
	if not building:
		return
	if not building_model:
		return
	if not building_model.has_method(&"set_progress"):
		return
	building_model.set_progress(building.progress)

# 把 backend 展示仓转发给 model,由其绑定到 ItemStack(见 ItemStack.bind;解绑时 bag 传 null)。
func _bind_display_bag():
	if not building_model or not building_model.has_method(&"bind_bag"):
		return
	var display_bag: Bag = null
	if building and building.has_method(&"get_display_bag"):
		display_bag = building.get_display_bag()
	building_model.bind_bag(display_bag)
