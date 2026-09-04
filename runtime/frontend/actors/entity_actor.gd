extends Node3D
class_name EntityActor

const COLOR_ENEMY: Color = Color(0.92, 0.24, 0.2)
const COLOR_FRIENDLY: Color = Color(0.3, 0.85, 0.35)
# 血条底边相对头顶投影点的上移间隙(像素)
const HEALTH_BAR_GAP: float = 12.0

var entity: Entity = null
var type: String = ""
var model: Node3D = null
var state: String = ""
# 模型在 actor 本地世界坐标里的头顶高度,由包围盒算出,供血条定位
var model_height: float = 0.0
# 填充 StyleBoxFlat 是 tscn 内共享 SubResource,需按实例复制后再按阵营染色
var _health_fill_style: StyleBoxFlat = null

@onready var health_bar: ProgressBar = %health_bar

func bind(in_entity: Entity):
	if entity:
		entity.position_changed.disconnect(_on_entity_position_changed)
		entity.direction_changed.disconnect(_on_entity_direction_changed)
		entity.state_changed.disconnect(_on_entity_state_changed)
		if entity is Creature:
			entity.health_changed.disconnect(_on_entity_health_changed)
	entity = in_entity
	if not entity:
		if health_bar:
			health_bar.hide()
		return
	if entity.type != type:
		_on_entity_type_changed()
	_on_entity_position_changed()
	_on_entity_direction_changed()
	if entity.state != state:
		_on_entity_state_changed()
	entity.position_changed.connect(_on_entity_position_changed)
	entity.direction_changed.connect(_on_entity_direction_changed)
	entity.state_changed.connect(_on_entity_state_changed)
	if entity is Creature:
		entity.health_changed.connect(_on_entity_health_changed)
	_refresh_health_bar()
	name = "%d (%s)" % [entity.id, get_type_key()]

func get_type_key() -> String:
	return "Entity_%s" % type

func _on_entity_position_changed():
	if not entity:
		return
	position = Vector3(entity.position.x, 0, entity.position.y)

func _on_entity_direction_changed():
	if not entity:
		return
	if entity.direction != Vector2.ZERO:
		look_at(global_position + Vector3(entity.direction.x, 0, entity.direction.y))

func _on_entity_type_changed():
	type = entity.type
	model_height = 0.0
	if model:
		remove_child(model)
		model.queue_free()
	var entity_path: String = "res://runtime/frontend/models/entities/%s/%s.tscn" % [type, type]
	var entity_scene: PackedScene = load(entity_path)
	assert(entity_scene, "Could not find scene of %s" % type)
	model = entity_scene.instantiate()
	if model:
		add_child(model)
		model.owner = owner
		model.scale = Vector3.ONE * 0.3
		model_height = _compute_model_height()

# 取模型全部 VisualInstance 包围盒合并后的世界高度(相对 actor 原点,即地面)
func _compute_model_height() -> float:
	if not model or not is_inside_tree():
		return 0.0
	var top_y: float = 0.0
	for visual: VisualInstance3D in _collect_visual_instances(model):
		var world_aabb: AABB = visual.global_transform * visual.get_aabb()
		if world_aabb.end.y > top_y:
			top_y = world_aabb.end.y
	return top_y - global_position.y

func _collect_visual_instances(in_node: Node) -> Array[VisualInstance3D]:
	var visuals: Array[VisualInstance3D] = []
	for child in in_node.get_children():
		if child is VisualInstance3D:
			visuals.append(child as VisualInstance3D)
		visuals.append_array(_collect_visual_instances(child))
	return visuals

func _on_entity_state_changed():
	state = entity.state
	model.set_state(state)

# —— 血条 ——

func _on_entity_health_changed():
	_refresh_health_bar()

# 血量变化时刷新填充值与颜色;显隐由 _process 每帧按 health 判定。
func _refresh_health_bar():
	if not entity or entity is not Creature:
		return
	var creature: Creature = entity as Creature
	if creature.health <= 0.0 or creature.health >= creature.max_health:
		return
	if _health_fill_style == null:
		_ensure_fill_style()
	_health_fill_style.bg_color = COLOR_ENEMY if entity is Enemy else COLOR_FRIENDLY
	health_bar.max_value = 100.0
	health_bar.value = creature.health / creature.max_health * 100.0

# 复制 tscn 里的共享 fill StyleBoxFlat,避免改色污染所有血条实例
func _ensure_fill_style():
	_health_fill_style = (health_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	health_bar.add_theme_stylebox_override("fill", _health_fill_style)

func _process(_in_delta: float):
	if not entity or entity is not Creature:
		return
	var creature: Creature = entity as Creature
	if creature.health >= creature.max_health or creature.health <= 0.0:
		health_bar.hide()
		return
	if model_height <= 0.0:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	# 沿相机 up 方向抬升,得到模型顶上一基准点;投影后把血条居中放到该点上方。
	var anchor: Vector3 = Vector3(entity.position.x, 0, entity.position.y) + camera.transform.basis.y * (model_height + 0.1)
	if camera.is_position_behind(anchor):
		health_bar.hide()
		return
	var screen: Vector2 = camera.unproject_position(anchor)
	health_bar.position = Vector2(screen.x - health_bar.size.x * 0.5, screen.y - health_bar.size.y - HEALTH_BAR_GAP)
	health_bar.show()
