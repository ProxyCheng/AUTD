extends Node3D
class_name EntityActor

# 携带物相对模型头顶的抬升间隙(米)
const CARRY_HEAD_GAP: float = 0.08
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
	entity = in_entity
	if not entity:
		if health_bar:
			health_bar.configure(null)
		_bind_carried()
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
	health_bar.configure(entity as Creature)
	_bind_carried()
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

# —— 头顶携带物(Labor.carried_bag) ——

# 头顶携带物通用组件:场景节点 %carried(几何在 entity_actor.tscn 里配),业务层只需给锚点。
@onready var _carried_stack: ItemStack = %carried
# 绑定的随身仓(Labor.carried_bag);类型/数量变化由 ItemStack.bind 跟随。
var _carried_bag: Bag = null

# 绑定工人的随身仓(Labor.carried_bag)到头顶 ItemStack,并跟随其数量变化(先断旧仓连接,防重绑重复回调)。
func _bind_carried():
	if is_instance_valid(_carried_bag) and _carried_bag.count_changed.is_connected(_sync_carried):
		_carried_bag.count_changed.disconnect(_sync_carried)
	var labor := entity as Labor
	_carried_bag = labor.carried_bag if labor and is_instance_valid(labor.carried_bag) else null
	if _carried_stack:
		_carried_stack.bind(_carried_bag)
	if is_instance_valid(_carried_bag) and not _carried_bag.count_changed.is_connected(_sync_carried):
		_carried_bag.count_changed.connect(_sync_carried)
	_sync_carried()

func _sync_carried():
	if not entity or entity is not Labor or not is_instance_valid(_carried_bag):
		_hide_carried()
		return
	if _carried_bag.count <= 0 or _carried_bag.item_type.is_empty():
		_hide_carried()
		return
	# 头顶锚点 = 模型本地合并 AABB 的顶面中心(actor 局部坐标,随 yaw 一起转);
	# 携带物垛底面贴住该锚点 + 抬升间隙。
	var top_center: Vector3 = _model_local_box.get_center()
	_carried_stack.position = Vector3(top_center.x, _model_local_box.end.y + CARRY_HEAD_GAP, top_center.z)
	# 目标长度随模型身高缩放(约身高 2/3,下限保证醒目);按物品原始长轴换算成节点 scale。
	var target_len: float = _carried_target_length()
	_carried_stack.scale = Vector3.ONE * (target_len / maxf(_carried_stack.long_axis(), 0.0001))
	if not _carried_stack.visible:
		_carried_stack.show()

func _hide_carried():
	if _carried_stack:
		_carried_stack.hide()

# 携带物目标长度(横躺长轴),约模型身高 2/3,下限保证足够醒目
func _carried_target_length() -> float:
	return maxf(model_height * 0.6, 0.25)
