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

# —— 音效 ——
# 脚步:行走状态按间隔播放(带轻微音高抖动);受击/死亡由 state 变化驱动
# (dizzy=受击,die=死亡),不逐帧触发,避免噪声。
const FOOTSTEP_INTERVAL: float = 0.42
const FOOTSTEP_VOLUME_DB: float = -10.0

var _footstep_timer: float = 0.0

# 头顶条组:血条 + 手持工具耐久条竖排(组统一做 billboard 定位,子条自身不定位)。
@onready var head_bars: HeadBarGroup = %head_bars
# 手持工具的堆叠表现(绑工人手持仓 tool_bag,场景配置成只显示 1 件)。
@onready var _tool_stack: ItemStack = %tool

func bind(in_entity: Entity):
	if entity:
		entity.position_changed.disconnect(_on_entity_position_changed)
		entity.direction_changed.disconnect(_on_entity_direction_changed)
		entity.state_changed.disconnect(_on_entity_state_changed)
	entity = in_entity
	if not entity:
		if head_bars:
			head_bars.bind_source(null)
		_bind_carried()
		_bind_tool()
		return
	if entity.type != type:
		_on_entity_type_changed()
	# 池复用重绑:模型实例沿用上一发的,但已换绑到新实体 —— 通知模型清掉上一发残留的
	# 一次性表现(如炮弹尾迹粒子),否则残留粒子会随模型被瞬移到新发射点、拖成一条直线。
	# 与 §5.7 音频"重绑时对齐状态、防补播"同一思路。
	if model and model.has_method(&"on_rebind"):
		model.on_rebind()
	_on_entity_position_changed()
	_on_entity_direction_changed()
	if entity.state != state:
		_on_entity_state_changed()
	entity.position_changed.connect(_on_entity_position_changed)
	entity.direction_changed.connect(_on_entity_direction_changed)
	entity.state_changed.connect(_on_entity_state_changed)
	head_bars.bind_source(entity)
	_bind_carried()
	_bind_tool()
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

# 飞行物(Ballistic)表现:把 backend 的平面轨迹数据转发给模型,由模型负责抛物线 Y 与俯仰朝向。
# 以"模型是否实现 set_flight"为能力判据——非飞行模型直接跳过(保持贴地、水平朝向)。
func _sync_flight() -> bool:
	if not model or not model.has_method(&"set_flight"):
		return false
	var ballistic: Ballistic = entity as Ballistic
	if not ballistic:
		return false
	model.set_flight(ballistic.flight_progress(), ballistic.direction, ballistic.move_speed, ballistic.flight_distance)
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
		_bind_tool_mount()

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
	# 条组复用同一模型度量,挂上测量结果
	if head_bars:
		head_bars.setup(self, model)

func _on_entity_state_changed():
	state = entity.state
	if model and model.has_method(&"set_state"):
		model.set_state(state)
	match state:
		"dizzy":
			AudioManager.sfx_at(&"hit", global_position, randf_range(0.95, 1.05))
		"die":
			if type == "enemy":
				AudioManager.sfx_at(&"voice_enemy", global_position, randf_range(0.9, 1.05))
			else:
				AudioManager.sfx_at(&"die", global_position, randf_range(0.9, 1.05))

func _process(in_delta: float):
	_tick_footstep(in_delta)
	_sync_tool_transform()

# 脚步音:仅地面行走单位且 actor 可见时出声(离屏/飞行物不播);非行走状态清零计时。
func _tick_footstep(in_delta: float):
	if state != "walk" or entity is Ballistic or not is_visible_in_tree():
		_footstep_timer = 0.0
		return
	_footstep_timer -= in_delta
	if _footstep_timer > 0.0:
		return
	_footstep_timer = FOOTSTEP_INTERVAL
	# 脚步高频且低优先级:池满时丢弃,不抢占弩机/受击等关键音。
	AudioManager.sfx_at(&"footstep", global_position, randf_range(0.92, 1.08), FOOTSTEP_VOLUME_DB, true)

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
	if _carried_bag.count_of(_carried_bag.item_type) <= 0 or _carried_bag.item_type.is_empty():
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

# —— 手持工具(Labor.tool_bag) ——

# 手持工具挂点:模型无手部骨骼(labor 的 fbx 是静态网格),故把工具挂在**身体右缘之外**
# 近似"手持"。挂点必须由模型包围盒外推得出 —— 用身高比例给固定偏移会把工具埋进身体里
# (实测模型 x∈[-0.15,0.12],固定偏移落在 0.07 → 整根被遮住)。间隙按身高比例换算。
const TOOL_HOLD_GAP_RATIO: float = 0.06
# 工具显示长度(横躺长轴),约模型身高四成,下限保证足够醒目。
const TOOL_LENGTH_RATIO: float = 0.4
const TOOL_MIN_LENGTH: float = 0.12

# 工具挂点:模型可提供 tool_mount()(返回会随劳作动画晃动的节点,如 LaborModel 的 $labor);
# 没有该方法时退回 actor 根(工具不随身体动画,但也不会出错)。
var _tool_mount: Node3D = null
# 工具在"挂点本地空间"下的固定姿态:由 _sync_tool 算一次,每帧由 _sync_tool_transform 套用。
var _tool_local_transform: Transform3D = Transform3D.IDENTITY

# 绑定工具挂点(模型就绪后调用)。工具本体**不** reparent 进模型 —— 模型换绑/回收时会连带
# 释放子节点,而工具要跨重绑存活;改为每帧把挂点变换换算到工具上(见 _sync_tool_transform)。
func _bind_tool_mount():
	_tool_mount = self
	if model and model.has_method(&"tool_mount"):
		var mount: Variant = model.call(&"tool_mount")
		if mount is Node3D:
			_tool_mount = mount

# 把 %tool 堆叠绑到随身仓里"工具那一格"(工具是随身仓里的有状态单体,见 Bag/Labor);
# 先断旧仓连接,防重绑重复回调。
func _bind_tool():
	if is_instance_valid(_carried_bag) and _carried_bag.count_changed.is_connected(_sync_tool):
		_carried_bag.count_changed.disconnect(_sync_tool)
	if _tool_stack:
		_tool_stack.bind(_carried_bag, _tool_type())
	if is_instance_valid(_carried_bag) and not _carried_bag.count_changed.is_connected(_sync_tool):
		_carried_bag.count_changed.connect(_sync_tool)
	_sync_tool()

# 算出工具在挂点本地空间的固定姿态(挂点自带模型缩放,故长度要除掉该缩放);无工具则隐藏。
# 挂点变换每帧由 _sync_tool_transform 套用 —— 这样劳作时身体晃、工具跟着晃。
func _sync_tool():
	if not _tool_stack:
		return
	if not entity or entity is not Labor or not is_instance_valid(_carried_bag):
		_tool_stack.hide()
		return
	var tool := _held_tool()
	if tool == null:
		_tool_stack.hide()
		return
	# 工具类型可能刚变(取/还工具),绑定的展示格跟着切
	if _tool_stack.bind_type != tool.type:
		_tool_stack.bind(_carried_bag, tool.type)
	# 挂点 → actor 的变换链(挂点是模型子树,含模型的缩放/朝向)
	var chain: Transform3D = HeadBar.chain_to(_tool_mount if _tool_mount else self, self)
	var mount_scale: float = maxf(chain.basis.get_scale().x, 0.0001)
	# 期望长度(actor 空间)→ ItemStack 节点 scale(挂点本地空间)
	var target_len: float = maxf(model_height * TOOL_LENGTH_RATIO, TOOL_MIN_LENGTH)
	var node_scale: float = target_len / maxf(_tool_stack.long_axis(), 0.0001) / mount_scale
	# 绕 Y 转 90°:ItemStack 约定长轴沿挂点 +Z,转后长轴横在工人右侧(actor 局部 +X)
	var local := Transform3D(
			Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)).scaled(Vector3.ONE * node_scale),
			Vector3.ZERO)
	# 落位:身体右缘 + 半个工具长 + 间隙 → 整件工具都在身体之外,不会被遮住
	var center: Vector3 = _model_local_box.get_center()
	local.origin = chain.affine_inverse() * Vector3(
			_model_local_box.end.x + target_len * 0.5 + model_height * TOOL_HOLD_GAP_RATIO,
			center.y,
			center.z)
	_tool_local_transform = local
	_tool_stack.transform = chain * local
	_tool_stack.show()

# 每帧把挂点(随劳作动画晃动的身体节点)的当前变换套到工具上 —— 身体晃,工具跟着晃。
func _sync_tool_transform():
	if not _tool_stack or not _tool_stack.visible:
		return
	if _tool_mount == null or _tool_mount == self:
		return
	_tool_stack.transform = HeadBar.chain_to(_tool_mount, self) * _tool_local_transform

# 随身仓里那件工具(有状态单体);无 / 已 freed / 非 Tool 时返回 null。
func _held_tool() -> Tool:
	var carrier: Object = _carried_bag.peek_state() if is_instance_valid(_carried_bag) else null
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool

# 随身仓里那件工具的类型;无工具时返回 ""。
func _tool_type() -> String:
	var tool := _held_tool()
	if tool == null:
		return ""
	return tool.type
