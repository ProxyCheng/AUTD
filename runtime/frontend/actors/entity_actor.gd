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

# —— 选中高亮 ——
# 选中状态由 frontend(LevelActor.selected_target)持有;本 actor 只是表现层:
# set_selected(true/false) 显隐选中环,不接触 backend 玩法。
var selected: bool = false
var _selection_ring: Node3D = null

# —— 音效 ——
# 脚步:行走状态按间隔播放(带轻微音高抖动);受击/死亡由 state 变化驱动
# (dizzy=受击,die=死亡),不逐帧触发,避免噪声。
const FOOTSTEP_INTERVAL: float = 0.42
const FOOTSTEP_VOLUME_DB: float = -10.0

var _footstep_timer: float = 0.0

# 头顶条组:血条 + 手持工具耐久条竖排(组统一做 billboard 定位,子条自身不定位)。
@onready var head_bars: HeadBarGroup = %head_bars
# 手持工具的堆叠表现(绑工人手上仓 hand_bag,场景配置成只显示 1 件)。
@onready var _tool_stack: ItemStack = %tool

func bind(in_entity: Entity):
	# 重绑(复用池回收/重建)时复位选中,避免上个实体的高亮残留。
	selected = false
	if _selection_ring:
		_selection_ring.visible = false
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

# 显隐选中环(点击选中工人等实体时由 LevelActor 驱动)。
func set_selected(in_selected: bool):
	if in_selected == selected:
		return
	selected = in_selected
	if not _selection_ring:
		_build_selection_ring()
	if _selection_ring:
		_selection_ring.visible = selected

# 程序化生成选中环:与 BuildingActor 同款 TorusMesh(默认平躺 XZ 面,勿再绕 X 旋转),
# 但半径由模型本地包围盒推出 —— 工人远小于 1×1 建筑,不能沿用建筑的硬编码半径。
func _build_selection_ring():
	var outer: float = maxf(maxf(_model_local_box.size.x, _model_local_box.size.z) * 0.75, 0.15)
	var ring := MeshInstance3D.new()
	ring.name = "SelectionRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = outer * 0.75
	ring_mesh.outer_radius = outer
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

# 世界空间射线 vs 模型本地包围盒的 slab 测试:委托共享实现 ActorPick(建筑同款,唯一一份)。
func ray_hit_distance(in_origin: Vector3, in_direction: Vector3) -> float:
	return ActorPick.hit_distance(in_origin, in_direction, _model_local_box, global_transform)

# 点击命中的 backend 目标:与 BuildingActor 统一访问器,供 LevelActor.pick_target 取回。
func pick_target() -> Object:
	return entity

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

# —— 头顶携带物(Labor.head_bag) ——

# 头顶携带物通用组件:场景节点 %carried(几何在 entity_actor.tscn 里配),业务层只需给锚点。
@onready var _carried_stack: ItemStack = %carried
# 绑定的头顶货仓(Labor.head_bag,装载的散料);类型/数量变化由 ItemStack.bind 跟随。
var _head_bag: Bag = null

# 绑定工人的头顶货仓(Labor.head_bag)到头顶 ItemStack,并跟随其数量/类型变化(先断旧仓连接,防重绑重复回调)。
# 两个信号都要接:头顶垛的显隐与姿态读的是 (件数, 类型) 两者 —— 只接 count_changed 的话,
# 类型晚于件数到达时(计时搬运"到点才入仓",而主要类型由取货叶子在搬运落地后才写)会先按空类型
# 判成"没货"而隐藏,之后类型补上也再没人来显示它。
func _bind_carried():
	if is_instance_valid(_head_bag):
		if _head_bag.count_changed.is_connected(_sync_carried):
			_head_bag.count_changed.disconnect(_sync_carried)
		if _head_bag.item_type_changed.is_connected(_sync_carried):
			_head_bag.item_type_changed.disconnect(_sync_carried)
	var labor := entity as Labor
	_head_bag = labor.head_bag if labor and is_instance_valid(labor.head_bag) else null
	if _carried_stack:
		_carried_stack.bind(_head_bag)
	if is_instance_valid(_head_bag):
		if not _head_bag.count_changed.is_connected(_sync_carried):
			_head_bag.count_changed.connect(_sync_carried)
		if not _head_bag.item_type_changed.is_connected(_sync_carried):
			_head_bag.item_type_changed.connect(_sync_carried)
	_sync_carried()

func _sync_carried():
	if not entity or entity is not Labor or not is_instance_valid(_head_bag):
		_hide_carried()
		return
	if _head_bag.count_of(_head_bag.item_type) <= 0 or _head_bag.item_type.is_empty():
		_hide_carried()
		return
	# 头顶锚点 = 模型本地合并 AABB 的顶面中心(actor 局部坐标,随 yaw 一起转);
	# 携带物垛底面贴住该锚点 + 抬升间隙。
	var top_center: Vector3 = _model_local_box.get_center()
	_carried_stack.position = Vector3(top_center.x, _model_local_box.end.y + CARRY_HEAD_GAP, top_center.z)
	_carried_stack.scale = Vector3.ONE * _carried_scale_for(_head_bag.item_type)
	if not _carried_stack.visible:
		_carried_stack.show()

func _hide_carried():
	if _carried_stack:
		_carried_stack.hide()

# 携带物目标长度(横躺长轴),约模型身高 2/3,下限保证足够醒目
func _carried_target_length() -> float:
	return maxf(model_height * 0.6, 0.25)

# 头顶携带物该用的节点 scale:**按类型**换算(期望长度 ÷ 该类型原始长轴),不看本垛此刻的读数。
# 这样"还没进垛的那件"也能算出落地后多大 —— 搬运飞行的终点尺寸正是靠它,否则垛空着时
# 只能读到上一次类型甚至场景默认的 scale,飞行会按错尺寸收尾、到位才被 _sync_carried 改回来。
func _carried_scale_for(in_item_type: String) -> float:
	if not _carried_stack:
		return 1.0
	return _carried_stack.scale_for(in_item_type, _carried_target_length())

# —— 手持工具(Labor.hand_bag) ——

# 手持工具挂点:模型无手部骨骼(labor 的 fbx 是静态网格),故把工具挂在**身体右缘之外**
# 近似"手持"。挂点必须由模型包围盒外推得出 —— 用身高比例给固定偏移会把工具埋进身体里
# (实测模型 x∈[-0.15,0.12],固定偏移落在 0.07 → 整根被遮住)。间隙按身高比例换算。
const TOOL_HOLD_GAP_RATIO: float = 0.06
# 工具显示长度(横躺长轴),约模型身高四成,下限保证足够醒目。
const TOOL_LENGTH_RATIO: float = 0.4
const TOOL_MIN_LENGTH: float = 0.12

# 绑定的手上仓(Labor.hand_bag,容量 1,工具是里面唯一那件);工具那格由 ItemStack.bind 跟随。
var _hand_bag: Bag = null

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

# 把 %tool 堆叠绑到手上仓(Labor.hand_bag)那件工具上(有状态单体,容量 1,见 Bag/Labor);
# 先断旧仓连接,防重绑重复回调。
func _bind_tool():
	if is_instance_valid(_hand_bag) and _hand_bag.count_changed.is_connected(_sync_tool):
		_hand_bag.count_changed.disconnect(_sync_tool)
	var labor := entity as Labor
	_hand_bag = labor.hand_bag if labor and is_instance_valid(labor.hand_bag) else null
	# 不带类型参数:手仓只装手上这一件**有状态单体**,其类型记在载体(Tool)上、不在 bag.item_type 上,
	# 由 ItemStack 自行解析(见 _display_type);手仓容量 1,来件/换件都表现为 count_changed,
	# 故换工具(斧↔镐)也能被察觉,无需外部重绑。这里若传了类型,bind_type 就恒非空、外部再无从察觉换件。
	if _tool_stack:
		_tool_stack.bind(_hand_bag)
	if is_instance_valid(_hand_bag) and not _hand_bag.count_changed.is_connected(_sync_tool):
		_hand_bag.count_changed.connect(_sync_tool)
	_sync_tool()

# 算出工具在挂点本地空间的固定姿态(挂点自带模型缩放,故长度要除掉该缩放);无工具则隐藏。
# 挂点变换每帧由 _sync_tool_transform 套用 —— 这样劳作时身体晃、工具跟着晃。
func _sync_tool():
	if not _tool_stack:
		return
	if not entity or entity is not Labor or not is_instance_valid(_hand_bag):
		_tool_stack.hide()
		return
	var tool := _held_tool()
	if tool == null:
		_tool_stack.hide()
		return
	# 展示类型由 ItemStack 自己解析(手仓没有 item_type,它回退到载体类型,见 _bind_tool 注释),这里只管姿态。
	# 挂点 → actor 的变换链(挂点是模型子树,含模型的缩放/朝向)
	var chain: Transform3D = HeadBar.chain_to(_tool_mount if _tool_mount else self, self)
	# 期望长度(actor 空间)→ ItemStack 节点 scale(挂点本地空间),按类型换算(见 _tool_scale_for)
	var node_scale: float = _tool_scale_for(tool.type)
	# 先绕 X 转 −90° 把工具立起来:ItemStack 局部空间里长轴沿 +Z、刀头在 +Z 端(实测:转 +90° 会朝下),
	# 转后刀头朝上(actor 局部 +Y)。
	# 再绕工具自身长轴(Z)转 −90°:局部 −X 是刀头指向(ItemStack 约定"宽=X"、§8 约定"刀头朝 −X"),
	# 转后刀刃朝正前(actor 局部 −Z,与普通实体 look_at 的前向一致);不转的话刀刃横指身体一侧。
	# 两步都经实测校验:局部 +Z → +Y(朝上)、局部 −X → −Z(朝前)。
	var local := Transform3D(
			(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0))
					* Basis.from_euler(Vector3(0.0, 0.0, -PI * 0.5))).scaled(Vector3.ONE * node_scale),
			Vector3.ZERO)
	# 落位:身体右缘 + 间隙 —— 工具已竖直,中心不再需要偏出半个长度;整件工具都在身体之外,不会被遮住
	var center: Vector3 = _model_local_box.get_center()
	local.origin = chain.affine_inverse() * Vector3(
			_model_local_box.end.x + model_height * TOOL_HOLD_GAP_RATIO,
			center.y,
			center.z)
	_tool_local_transform = local
	_tool_stack.transform = chain * local
	_tool_stack.show()

# 手上工具的**世界空间**目标尺寸(actor 自身无缩放,故 actor 空间同值):期望长度 ÷ 该类型原始长轴。
# 飞行端点用这个 —— 它与 _tool_stack 的节点 scale 是同一把尺子(见 _sync_tool 的 chain * local)。
func _tool_world_scale_for(in_tool_type: String) -> float:
	if not _tool_stack:
		return 1.0
	var target_len: float = maxf(model_height * TOOL_LENGTH_RATIO, TOOL_MIN_LENGTH)
	return _tool_stack.scale_for(in_tool_type, target_len)

# 挂点**本地空间**的目标 scale(供 _sync_tool 写进 _tool_stack.transform):挂点自带模型缩放,
# 故要把世界尺寸除掉它。**别拿它当世界尺寸用** —— 两者差一个挂点缩放(实测差 8 倍,飞行会变成巨物)。
func _tool_scale_for(in_tool_type: String) -> float:
	return _tool_world_scale_for(in_tool_type) / _tool_mount_scale()

# 工具挂点的累计缩放(挂点是模型子树,含模型自身的缩放)。
func _tool_mount_scale() -> float:
	return maxf(HeadBar.chain_to(_tool_mount if _tool_mount else self, self).basis.get_scale().x, 0.0001)

# 每帧把挂点(随劳作动画晃动的身体节点)的当前变换套到工具上 —— 身体晃,工具跟着晃。
func _sync_tool_transform():
	if not _tool_stack or not _tool_stack.visible:
		return
	if _tool_mount == null or _tool_mount == self:
		return
	_tool_stack.transform = HeadBar.chain_to(_tool_mount, self) * _tool_local_transform

# 手上仓里那件工具(有状态单体);无 / 已 freed / 非 Tool 时返回 null。
func _held_tool() -> Tool:
	var carrier: Object = _hand_bag.peek_state() if is_instance_valid(_hand_bag) else null
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool

# —— 物品搬运表现(随身仓 ⇄ 建筑仓) ——

# 起**一段**搬运飞行(第 in_index 件):把这次搬运的两端解成世界姿态,造一个 ItemFlight 交给
# in_host 托管,由搬运自己的 progress 驱动(见 ItemFlight)。由 RoomActor 在 item_departed 时调用。
func spawn_transfer_flight(in_transfer: ItemTransfer, in_index: int, in_host: Node):
	var worker_bag: Bag = _worker_bag_of(in_transfer)
	if not worker_bag:
		return
	var other_bag: Bag = in_transfer.dest_bag if worker_bag == in_transfer.source_bag else in_transfer.source_bag
	# building side: the landing rule (visible pile -> that piece's slot, otherwise shrink to the building center) has
	# its single implementation in BuildingActor.get_landing_anchor -- it takes the pile by "the bag actually moving
	# this time", so multi-bag buildings (workshops) do not draw the goods onto a different stack; no visible pile
	# (workshop input bag / main_base) -> model center + scale 0, reads as "vanishes on arrival" (on pickup it is
	# reversed: grows out of center 0 then flies to the worker).
	var building_anchor: Transform3D = Transform3D.IDENTITY
	var building_actor: BuildingActor = _building_actor_of(other_bag)
	if not building_actor:
		return
	building_anchor = building_actor.get_landing_anchor(other_bag, in_transfer.item_type)
	var worker_anchor: Transform3D = _worker_bag_anchor(worker_bag, in_transfer.item_type)
	var outgoing: bool = worker_bag == in_transfer.source_bag
	var from_pose: Transform3D = worker_anchor if outgoing else building_anchor
	var to_pose: Transform3D = building_anchor if outgoing else worker_anchor
	var flight: ItemFlight = ItemFlight.launch(in_transfer.item_type, from_pose, to_pose)
	if not flight:
		return
	in_host.add_child(flight)
	# 窗口按**计划件数**切(与后端 _advance 的分段同一把尺子),不是按已取件数 —— 两者必须一致。
	flight.follow(in_transfer, in_index, in_transfer.amount)

# 这次搬运里属于本工人的那只仓(头顶仓 / 手仓);两端都不是本人的 → null。
# 先 is_instance_valid 再比:搬运期间任一端仓可能已被销毁,拿 freed 实例做 `==` 会崩。
func _worker_bag_of(in_transfer: ItemTransfer) -> Bag:
	if is_instance_valid(in_transfer.source_bag) \
			and (in_transfer.source_bag == _head_bag or in_transfer.source_bag == _hand_bag):
		return in_transfer.source_bag
	if is_instance_valid(in_transfer.dest_bag) \
			and (in_transfer.dest_bag == _head_bag or in_transfer.dest_bag == _hand_bag):
		return in_transfer.dest_bag
	return null

# 对面那只仓所属建筑的 actor;仓挂在建筑下(随身仓挂在 Labor 下),建筑离屏未放置 → null。
func _building_actor_of(in_bag: Bag) -> BuildingActor:
	if not is_instance_valid(in_bag):
		return null
	var building: Building = in_bag.get_parent() as Building
	if not building:
		return null
	var level_actor := owner as LevelActor
	if not level_actor:
		return null
	return level_actor.get_building_actor(building)

# 工人侧锚点:头顶仓 → 头顶携带物垛,手仓 → 手持工具垛。两者都是 ItemStack,起/落点取
# "那一件在垛里的槽位"(见 ItemStack.next_slot_transform),与 _sync_carried/_sync_tool
# 维护的是同一姿态。
# 位置/朝向取自槽位,但**尺寸按 in_item_type 单独算**:搬运开始时目标垛往往是空的
# (取货时货还在托管仓里飞),它的 scale 停在上一次的类型、甚至场景默认值上 ——
# 直接拿它当终点尺寸,飞行就会按错尺寸收尾、到位才被 _sync_carried 改回来(实测差过 3 倍)。
func _worker_bag_anchor(in_bag: Bag, in_item_type: String) -> Transform3D:
	var stack: ItemStack = null
	var expected_scale: float = 1.0
	if in_bag == _hand_bag and _tool_stack:
		stack = _tool_stack
		expected_scale = _tool_world_scale_for(in_item_type)
	elif _carried_stack:
		stack = _carried_stack
		expected_scale = _carried_scale_for(in_item_type)
	if not stack:
		return global_transform
	var anchor: Transform3D = stack.next_slot_transform(in_item_type)
	# 只换缩放、保留朝向。垛自身缩放正常非零,但万一为 0,orthonormalized() 会出 NaN。
	var rotation: Basis = anchor.basis.orthonormalized() if Trs.is_pose_valid(anchor) else Basis.IDENTITY
	anchor.basis = rotation.scaled(Vector3.ONE * expected_scale)
	return anchor
