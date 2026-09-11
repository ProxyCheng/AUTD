extends Node3D
class_name EntityActor

# 携带物显示上限(超出部分只显示这么多层,避免头顶堆太高)
const CARRY_VISIBLE_MAX: int = 5
# 携带物相对模型头顶的抬升间隙(米)
const CARRY_HEAD_GAP: float = 0.08
# 相邻两层垂直间距系数(相对道具厚度),留微缝防 z-fight(与料堆 LAYER_SPACING 同义)
const CARRY_LAYER_SPACING: float = 1.3
# 实体模型统一缩放(美术源按米制,缩到格子视觉尺度)
const MODEL_SCALE: float = 0.3

var entity: Entity = null
var type: String = ""
var model: Node3D = null
var state: String = ""
# 模型在 actor 本地世界坐标里的头顶高度,由包围盒算出,供携带物定位
var model_height: float = 0.0
# 模型本地空间合并 AABB(相对 actor 原点,随 scale/本地朝向不变),供头顶携带物定位
var _model_local_box: AABB = AABB()

@onready var health_bar: EntityHealthBar = %health_bar

func bind(in_entity: Entity):
	if entity:
		entity.position_changed.disconnect(_on_entity_position_changed)
		entity.direction_changed.disconnect(_on_entity_direction_changed)
		entity.state_changed.disconnect(_on_entity_state_changed)
		if entity.has_signal(&"carried_changed"):
			entity.carried_changed.disconnect(_sync_carried)
	entity = in_entity
	if not entity:
		if health_bar:
			health_bar.configure(null)
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
	# 携带物信号(搬运表现):count/count 变化时刷新头顶 ItemStack
	if entity.has_signal(&"carried_changed"):
		entity.carried_changed.connect(_sync_carried)
	health_bar.configure(entity as Creature)
	_sync_carried()
	name = "%d (%s)" % [entity.id, get_type_key()]

func get_type_key() -> String:
	return "Entity_%s" % type

func _on_entity_position_changed():
	if not entity:
		return
	position = Vector3(entity.position.x, 0, entity.position.y)
	_sync_flight()

func _on_entity_direction_changed():
	if not entity:
		return
	if entity.direction == Vector2.ZERO:
		return
	# 飞行物由模型按抛物线切线统一处理朝向;普通实体保持 -Z 前向水平 look_at。
	if not _sync_flight():
		look_at(global_position + Vector3(entity.direction.x, 0, entity.direction.y))

# 飞行物(Arrow)表现:把 backend 的弹道数据转发给模型,由模型负责抛物线 Y 与俯仰朝向。
# 以"模型是否实现 set_flight"为能力判据——非飞行模型直接跳过(保持贴地、水平朝向)。
func _sync_flight() -> bool:
	if not model or not model.has_method(&"set_flight"):
		return false
	var arrow: Arrow = entity as Arrow
	if not arrow:
		return false
	model.set_flight(arrow.flight_progress(), arrow.direction, arrow.launch_height, arrow.flight_time, arrow.move_speed)
	return true

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
		model.scale = Vector3.ONE * MODEL_SCALE
		_refresh_model_metrics()

# 刷新模型度量:本地合并 AABB(头顶携带物定位用)与头顶高度(血条用)。
# 变换链在 actor 本地空间求框(不含 actor 自身 yaw 朝向),故结果随朝向稳定:
# 顶面中心即"头顶锚点",由本地框直接得出,经 model 自身缩放正确映射到 actor 局部坐标。
# AABB 求框复用 HeadBar 的静态工具。
func _refresh_model_metrics():
	if not model:
		return
	_model_local_box = HeadBar.measure_box(model, self)
	if _model_local_box.size == Vector3.ZERO:
		return
	# 血条/携带物都在 actor 本地 y 上计算(actor 只绕 y 转向,本地 y = 世界 y)
	model_height = _model_local_box.end.y
	# 血条复用同一模型度量,挂上测量结果
	if health_bar:
		health_bar.setup(self, model)

func _on_entity_state_changed():
	state = entity.state
	if model and model.has_method(&"set_state"):
		model.set_state(state)

# —— 头顶携带物(Creature.carried_*) ——

# 头顶携带物通用组件:复用 ItemStack 渲染(平放摞垛),业务层只需给出锚点与计数。
var _carried_stack: ItemStack = null

func _sync_carried():
	if not entity or entity is not Creature or _carried_count_of_entity() <= 0:
		_hide_carried()
		return
	var creature: Creature = entity as Creature
	if creature.carried_item_type.is_empty():
		_hide_carried()
		return
	if not _carried_stack:
		_carried_stack = ItemStack.new()
		_carried_stack.name = "carried"
		# 头顶为单列纵向摞(CARRY_VISIBLE_MAX 层),不横排
		_carried_stack.per_row = 1
		_carried_stack.layer_count = CARRY_VISIBLE_MAX
		_carried_stack.layer_spacing = CARRY_LAYER_SPACING
		add_child(_carried_stack)
	# 头顶锚点 = 模型本地合并 AABB 的顶面中心(actor 局部坐标,随 yaw 一起转);
	# 携带物垛底面贴住该锚点 + 抬升间隙。
	var top_center: Vector3 = _model_local_box.get_center()
	_carried_stack.position = Vector3(top_center.x, _model_local_box.end.y + CARRY_HEAD_GAP, top_center.z)
	# 目标长度随模型身高缩放(约身高 2/3,下限保证醒目),其余尺寸复用默认
	_carried_stack.target_length = _carried_target_length()
	_carried_stack.set_item_type(creature.carried_item_type)
	_carried_stack.set_count(_carried_count_of_entity())
	if not _carried_stack.visible:
		_carried_stack.show()

func _hide_carried():
	if _carried_stack:
		_carried_stack.hide()

func _carried_count_of_entity() -> int:
	var creature := entity as Creature
	if not creature:
		return 0
	return creature.carried_count

# 携带物目标长度(横躺长轴),约模型身高 2/3,下限保证足够醒目
func _carried_target_length() -> float:
	return maxf(model_height * 0.6, 0.25)
