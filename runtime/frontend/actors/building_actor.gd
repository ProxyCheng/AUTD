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
