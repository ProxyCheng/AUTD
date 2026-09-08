extends Node3D
class_name EntityActor

const COLOR_ENEMY: Color = Color(0.92, 0.24, 0.2)
const COLOR_FRIENDLY: Color = Color(0.3, 0.85, 0.35)
# 血条底边相对头顶投影点的上移间隙(像素)
const HEALTH_BAR_GAP: float = 12.0
# 携带物显示上限(超出部分只显示这么多层,避免头顶堆太高)
const CARRY_VISIBLE_MAX: int = 5
# 携带物相对模型头顶的抬升间隙(米)
const CARRY_HEAD_GAP: float = 0.08
# 相邻两层垂直间距系数(相对道具厚度),留微缝防 z-fight(与料堆 LAYER_SPACING 同义)
const CARRY_LAYER_SPACING: float = 1.3

var entity: Entity = null
var type: String = ""
var model: Node3D = null
var state: String = ""
# 模型在 actor 本地世界坐标里的头顶高度,由包围盒算出,供血条定位
var model_height: float = 0.0
# 模型本地空间合并 AABB(相对 actor 原点,随 scale/本地朝向不变),供头顶携带物定位
var _model_local_box: AABB = AABB()
# 填充 StyleBoxFlat 是 tscn 内共享 SubResource,需按实例复制后再按阵营染色
var _health_fill_style: StyleBoxFlat = null
# 头顶携带物根节点(搬运时显示物品小模型)
var _carried_root: Node3D = null
var _carried_items: Array[Node3D] = []

@onready var health_bar: ProgressBar = %health_bar

func bind(in_entity: Entity):
	if entity:
		entity.position_changed.disconnect(_on_entity_position_changed)
		entity.direction_changed.disconnect(_on_entity_direction_changed)
		entity.state_changed.disconnect(_on_entity_state_changed)
		if entity is Creature:
			entity.health_changed.disconnect(_on_entity_health_changed)
			if entity.has_signal(&"carried_changed"):
				entity.carried_changed.disconnect(_sync_carried)
	entity = in_entity
	if not entity:
		if health_bar:
			health_bar.hide()
		_sync_carried()
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
		if entity.has_signal(&"carried_changed"):
			entity.carried_changed.connect(_sync_carried)
	_refresh_health_bar()
	_sync_carried()
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
		_refresh_model_metrics()

# 刷新模型度量:本地合并 AABB(头顶携带物定位用)与头顶高度(血条用)。
# 变换链在 actor 本地空间求框(不含 actor 自身 yaw 朝向),故结果随朝向稳定:
# 顶面中心即"头顶锚点",由本地框直接得出,经 model 自身缩放正确映射到 actor 局部坐标。
func _refresh_model_metrics():
	if not model:
		return
	_model_local_box = _measure_local_box_of(model)
	if _model_local_box.size == Vector3.ZERO:
		return
	# 血条/携带物都在 actor 本地 y 上计算(actor 只绕 y 转向,本地 y = 世界 y)
	model_height = _model_local_box.end.y

# 求 in_node 子树在"本 actor 本地坐标系"的合并 AABB(变换链累乘,不依赖 global)。
func _measure_local_box_of(in_node: Node3D) -> AABB:
	return _measure_box(in_node, self)

func _measure_local_box(in_node: Node3D) -> AABB:
	return _measure_box(in_node, in_node)

# 合并 in_node 子树所有 VisualInstance 的 AABB 到 in_probe 本地坐标系。
# 用 8 角点逐点变换(与 stockpile_model 同款),basis 含镜像/非等比缩放也正确。
func _measure_box(in_node: Node3D, in_probe: Node3D) -> AABB:
	var min_p := Vector3.INF
	var max_p := -Vector3.INF
	for visual: VisualInstance3D in _collect_visual_instances(in_node):
		var to_probe := _chain_to(visual, in_probe)
		var aabb: AABB = visual.get_aabb()
		var corners := [
			aabb.position,
			aabb.position + Vector3(aabb.size.x, 0, 0),
			aabb.position + Vector3(0, aabb.size.y, 0),
			aabb.position + Vector3(0, 0, aabb.size.z),
			aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
			aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
			aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
			aabb.end,
		]
		for corner in corners:
			var p: Vector3 = to_probe * corner
			min_p = min_p.min(p)
			max_p = max_p.max(p)
	if min_p == Vector3.INF:
		return AABB()
	return AABB(min_p, max_p - min_p)

# 逐级父链变换:返回把 in_node 本地坐标变换到 in_probe 本地坐标的 Transform3D
# (与 stockpile_model 同款;in_node 子树各 visual 均以自身为起点链到 actor 根)。
func _chain_to(in_node: Node3D, in_probe: Node3D) -> Transform3D:
	var acc := Transform3D.IDENTITY
	var current: Node3D = in_node
	while current != in_probe:
		acc = current.transform * acc
		current = current.get_parent() as Node3D
		if not current:
			break
	return acc

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

# —— 头顶携带物(Creature.carried_*) ——

func _sync_carried():
	_clear_carried_items()
	if not entity or entity is not Creature or _carried_count_of_entity() <= 0:
		if _carried_root:
			_carried_root.hide()
		return
	var creature: Creature = entity as Creature
	if creature.carried_item_type.is_empty():
		if _carried_root:
			_carried_root.hide()
		return
	if not _carried_root:
		_carried_root = Node3D.new()
		_carried_root.name = "carried"
		add_child(_carried_root)
	# 头顶锚点 = 模型本地合并 AABB 的顶面中心(actor 局部坐标,随 yaw 一起转);
	# 各层 item 沿该锚点的 +Y 逐层摞。
	var top_center: Vector3 = _model_local_box.get_center()
	_carried_root.position = Vector3(top_center.x, _model_local_box.end.y + CARRY_HEAD_GAP, top_center.z)
	var item_path: String = "res://runtime/frontend/models/entities/%s/%s.tscn" % [creature.carried_item_type, creature.carried_item_type]
	var item_scene: PackedScene = load(item_path)
	if not item_scene:
		return
	# 探针:量一个未缩放道具的本地盒(链式测量在 probe 本地系,与 probe 自身 scale 无关),
	# 后续按统一缩放因子换算真实尺寸/偏移。
	var probe: Node3D = item_scene.instantiate()
	var box: AABB = _measure_local_box(probe)
	probe.free()
	if box.size == Vector3.ZERO:
		_carried_root.hide()
		return
	var scale_factor: float = _carried_target_length() / maxf(box.size.x, box.size.z)
	# 缩放后真实层厚(含微缝);水平居中:使道具缩放后的 AABB 中心对准基座中心
	var layer_y: float = box.size.y * scale_factor * CARRY_LAYER_SPACING
	var bottom_y: float = box.position.y * scale_factor
	var center_x: float = (box.position.x + box.size.x * 0.5) * scale_factor
	var center_z: float = (box.position.z + box.size.z * 0.5) * scale_factor
	var count: int = mini(_carried_count_of_entity(), CARRY_VISIBLE_MAX)
	for i in range(count):
		var item: Node3D = item_scene.instantiate()
		_carried_root.add_child(item)
		item.owner = owner
		item.scale = Vector3.ONE * scale_factor
		# 平躺同向;第 i 层底边贴住层基座顶(y=0)再沿 +Y 摞高 i 层
		item.position = Vector3(-center_x, -bottom_y + i * layer_y, -center_z)
		_carried_items.append(item)
	_carried_root.show()

func _carried_count_of_entity() -> int:
	var creature := entity as Creature
	if not creature:
		return 0
	return creature.carried_count

func _clear_carried_items():
	for item: Node3D in _carried_items:
		if is_instance_valid(item):
			item.queue_free()
	_carried_items.clear()

# 携带物目标长度(横躺长轴),约模型身高 2/3,下限保证足够醒目
func _carried_target_length() -> float:
	return maxf(model_height * 0.6, 0.25)

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
