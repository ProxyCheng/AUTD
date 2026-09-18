extends Node3D
class_name BuildingActor

var building: Building = null
var type: String = ""
var building_model: Node3D = null
var axis: Vector2i = Vector2i.ZERO
var direction: Vector2i = Vector2i.UP
# 模型本地空间合并 AABB(相对 actor 原点,随 scale/本地朝向不变),点击拾取用。
var _model_local_box: AABB = AABB()

# 模型测量失败时的兜底拾取盒:以建筑所在格为脚印(actor 原点在格中心),保证建筑永远可点。
const FALLBACK_PICK_BOX: AABB = AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))

# —— 选中高亮 ——
# 选中状态由 frontend(LevelActor.selected_target)持有;本 actor 只是表现层:
# set_selected(true/false) 显隐选中地盘(SelectionRing),不接触 backend 玩法。
var selected: bool = false
var _selection_ring: Node3D = null

# —— 攻击范围显示 ——
# 选中攻击型建筑时,在其所在格铺一块半透明圆形范围面(半径取自 backend.get_attack_range())。
# 与 _selection_ring 同属表现层,由 set_selected 显隐;backend 不感知本节点。
var _range_indicator: Node3D = null

# —— 工作/开火音效 ——
# 建筑处于 "working" 时按固定间隔播放对应工种音(砍木/挖矿/打造),与模型工作循环同拍;
# 十字弩在 loading/firing 状态变化时各播一次。均由 state 驱动,不逐帧触发。
const WORK_SFX_INTERVAL: float = 0.55
const WORK_SFX_BY_TYPE: Dictionary = {
	&"tree_workshop": &"work_chop",
	&"stone_mine": &"work_mine",
	&"crafting_workshop": &"work_craft",
	&"tool_workshop": &"work_craft",
}
# 各工种音量偏移(dB):打造用的金属锅采样本身偏响,压一档避免盖过其它音。
const WORK_SFX_VOLUME_DB: Dictionary = {
	&"work_chop": -4.0,
	&"work_mine": -4.0,
	&"work_craft": -24.0,
}
var _work_sfx_cooldown: float = 0.0
# 上一次已发声的 building 状态:防滚动回可视区/复用池重绑时补播状态音。
var _last_state: String = ""

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
		if building.has_signal(&"load_progress_changed"):
			building.load_progress_changed.disconnect(_on_building_load_progress_changed)
		if building.has_signal(&"deliver_progress_changed"):
			building.deliver_progress_changed.disconnect(_on_building_deliver_progress_changed)
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
	# 上弦/装弹进度只有炮塔类建筑有(见 Turret.load_progress)
	if building.has_signal(&"load_progress_changed"):
		building.load_progress_changed.connect(_on_building_load_progress_changed)
	# delivery-action progress exists only on the conveyor (see Conveyor.deliver_progress)
	if building.has_signal(&"deliver_progress_changed"):
		building.deliver_progress_changed.connect(_on_building_deliver_progress_changed)
	if building.has_signal(&"aim_direction_changed"):
		building.aim_direction_changed.connect(_on_building_aim_direction_changed)
	# 数据源经组统一下发给全部子条(容量条 + 工作量条),各自按 _value() 决定显隐
	work_progress.bind_source(building)
	# 重绑时先把缓存对齐当前状态,避免滚动回可视区/复用池时补播一次状态音。
	_last_state = building.state
	_on_building_state_changed()
	_on_building_progress_changed()
	if building.has_signal(&"load_progress_changed"):
		_on_building_load_progress_changed()
	if building.has_signal(&"deliver_progress_changed"):
		_on_building_deliver_progress_changed()
	_on_building_aim_direction_changed()
	_bind_display_bag()
	_update_direction()

func get_type_key() -> String:
	return "Building_%s" % type

# 世界空间射线 vs 模型本地包围盒的 slab 测试:与实体 actor 共用 ActorPick(唯一实现)。
# 模型测量失败(空盒)时退回格子脚印盒,保证建筑不会因模型问题而不可点。
func ray_hit_distance(in_origin: Vector3, in_direction: Vector3) -> float:
	var box: AABB = _model_local_box
	if box.size == Vector3.ZERO:
		box = FALLBACK_PICK_BOX
	return ActorPick.hit_distance(in_origin, in_direction, box, global_transform)

# 点击命中的 backend 目标:与 EntityActor 统一访问器,供 LevelActor.pick_target 取回。
func pick_target() -> Object:
	return building

func _on_type_changed():
	if building_model:
		remove_child(building_model)
		building_model.queue_free()
	# 旧模型已释放:先清拾取盒;新模型测量失败时由 ray_hit_distance 退回格子脚印盒。
	_model_local_box = AABB()
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
		# 点击拾取的本地包围盒:与 entity_actor 同一度量工具(actor 本地空间,不含自身朝向)。
		_model_local_box = HeadBar.measure_box(building_model, self)

func _on_axis_changed():
	position = Vector3(axis.x, 0, axis.y)

func _on_direction_changed():
	look_at(global_position + Vector3(direction.x, 0, direction.y))

func _process(in_delta: float):
	_update_direction()
	_tick_work_sfx(in_delta)

# 工作音效:仅在 "working" 状态按固定间隔播放;非工作状态清零冷却,避免下次进入时立刻出声。
func _tick_work_sfx(in_delta: float):
	if not building or building.state != "working":
		_work_sfx_cooldown = 0.0
		return
	var sfx_id: StringName = WORK_SFX_BY_TYPE.get(StringName(building.type), &"")
	if sfx_id == &"":
		return
	_work_sfx_cooldown -= in_delta
	if _work_sfx_cooldown > 0.0:
		return
	_work_sfx_cooldown = WORK_SFX_INTERVAL
	AudioManager.sfx_at(sfx_id, global_position, randf_range(0.95, 1.05), WORK_SFX_VOLUME_DB.get(sfx_id, -4.0))

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
	_play_state_sfx(building.state)
	if not building_model:
		return
	if building_model.has_method(&"set_state"):
		building_model.set_state(building.state)
	# entering the delivery phase: resolve the landing pose for the model first, then refresh progress once -- the model cannot draw until it has an anchor
	if building.state == "delivering":
		_update_delivery_anchor()
	_on_building_deliver_progress_changed()

# 状态变化音效:仅在状态真正改变时播一次(防重绑补播)。
# 按建筑类型查表:类型无条目 / 该状态无音效则不发声。
# 值可为单发 id 或变体组 id(见 AudioLibrary):cannon_* 登记为多变体组,避免连发同音。
const STATE_SFX_BY_TYPE: Dictionary = {
	&"crossbow": {
		"loading": &"crossbow_load",
		"firing": &"crossbow_fire",
	},
	&"cannon": {
		"loading": &"cannon_load",
		"firing": &"cannon_fire",
	},
}

# 状态音的音高微调(按建筑类型):火炮是重炮,把金属撞击采样整体压低音高,读作闷重的炮声;
# 未登记的类型取 1.0。仍叠加在 _play_state_sfx 的 ±5% 随机抖动上,避免连发完全同音。
const STATE_SFX_PITCH_BY_TYPE: Dictionary = {
	&"cannon": 0.85,
}

func _play_state_sfx(in_state: String):
	if in_state == _last_state:
		return
	_last_state = in_state
	var by_state: Dictionary = STATE_SFX_BY_TYPE.get(StringName(building.type), {})
	var sfx_id: StringName = by_state.get(in_state, &"")
	if sfx_id == &"":
		return
	var pitch: float = STATE_SFX_PITCH_BY_TYPE.get(StringName(building.type), 1.0) * randf_range(0.95, 1.05)
	AudioManager.sfx_at(sfx_id, global_position, pitch)

func _on_building_progress_changed():
	if not building:
		return
	if not building_model:
		return
	if not building_model.has_method(&"set_progress"):
		return
	building_model.set_progress(building.progress)

# 上弦/装弹进度:仅炮塔类建筑有(见 Turret.load_progress),模型按需实现 set_load_progress
# (弩:端箭上弦;炮:炮弹入膛)。非炮塔建筑没有该信号,故只在信号存在时读取。
func _on_building_load_progress_changed():
	if not building or not building_model:
		return
	if not building_model.has_method(&"set_load_progress"):
		return
	building_model.set_load_progress(building.load_progress)

# delivery-action progress: only the conveyor has it (see Conveyor.deliver_progress), model optionally implements set_deliver_progress
func _on_building_deliver_progress_changed():
	if not building or not building_model:
		return
	if not building_model.has_method(&"set_deliver_progress"):
		return
	building_model.set_deliver_progress(building.deliver_progress)

# resolve "where the item being handed out will land" (world TRS) and give it to the model. the anchor must be
# computed before the item is committed to storage -- the goods are still in the conveyor's own bag right now and
# the downstream has not gained this piece yet, so the slot index at this instant is exactly the one it will take.
# only done when the building offers get_delivery_target (conveyor); like set_load_progress it is an optional presentation interface
func _update_delivery_anchor():
	if not building or not building_model:
		return
	if not building.has_method(&"get_delivery_target") or not building_model.has_method(&"set_delivery_anchor"):
		return
	var target: Building = building.get_delivery_target()
	if not target:
		return
	var held_type: String = ""
	if building.has_method(&"get_held_type"):
		held_type = building.get_held_type()
	var anchor: Transform3D
	var target_actor: BuildingActor = _building_actor_of(target)
	if target_actor:
		# take the anchor from "the bag that will actually accept it this time": with multi-bag buildings (workshops),
		# picking the wrong pile draws the goods onto a different stack. get_accept_bag is a backend read-only query
		# (the single implementation of the bag-selection rule), so the frontend does not duplicate that rule.
		var dest_bag: Bag = target.get_accept_bag(held_type)
		anchor = target_actor.get_landing_anchor(dest_bag, held_type)
	else:
		# downstream actor not placed (only hit at the edge of the camera's visible region): shrink to the cell center, reads as "vanishes on arrival"
		anchor = Trs.zero_scale(Vector3(target.axis.x, 0.0, target.axis.y))
	building_model.set_delivery_anchor(anchor)

# the actor for a building; off-screen actor not placed -> null. owner is the LevelActor (same lookup as EntityActor)
func _building_actor_of(in_building: Building) -> BuildingActor:
	var level_actor := owner as LevelActor
	if not level_actor:
		return null
	return level_actor.get_building_actor(in_building)

# 把 backend 展示仓转发给 model,由其绑定到 ItemStack(见 ItemStack.bind;解绑时 bag 传 null)。
func _bind_display_bag():
	if not building_model or not building_model.has_method(&"bind_bag"):
		return
	var display_bag: Bag = null
	if building and building.has_method(&"get_display_bag"):
		display_bag = building.get_display_bag()
	building_model.bind_bag(display_bag)

# 本建筑模型里**绑在 in_bag 上**的那只 ItemStack(料堆 / 备弹垛);该仓没有可见料堆 → null。
# 必须按"哪只仓在动"来取,不能取模型里第一只:多仓建筑(工坊有输入/产出好几只仓)的第一只
# 往往是产出堆,于是"给工坊送原木"会被画成飞进木板堆。无料堆的建筑(main_base 的模型没实现
# bind_bag)自然也是 null,调用方据此走"飞向建筑中心"。
func get_stack_for_bag(in_bag: Bag) -> ItemStack:
	if not is_instance_valid(in_bag) or not building_model:
		return null
	# 按全局类名找,料堆节点叫什么、挂在哪一层都不影响(炮塔挂在 %AmmoStack,工坊挂 content_stack)。
	for child: Node in building_model.find_children("*", "ItemStack", true, false):
		var stack: ItemStack = child
		if stack.bag == in_bag:
			return stack
	return null

# 建筑中心(世界空间):模型本地合并 AABB 的中心经 actor 变换;模型未就绪时退回 actor 原点(格中心)。
# 无料堆建筑的物品搬运落点用它(表现读作"飞到建筑中心并缩小到 0")。
func get_center_position() -> Vector3:
	if not building_model or _model_local_box.size == Vector3.ZERO:
		return global_position
	return global_transform * _model_local_box.get_center()

# the world TRS "the next item should have after landing" in a bag -- the endpoint of a transfer flight (see ItemFlight / conveyor delivery).
# visible pile -> the exact slot of that piece in the stack (each piece in a stack is placed per cell; using the stack origin directly would make
# the flight end one cell off); no visible pile (workshop input bag / main_base / model does not implement bind_bag) -> shrink to the building center,
# reads as "shrinks to nothing on arrival" (the zero-scale endpoint is handled by Trs.lerp). this is the single implementation of that rule
func get_landing_anchor(in_bag: Bag, in_item_type: String) -> Transform3D:
	var pile: ItemStack = get_stack_for_bag(in_bag)
	if pile:
		return pile.next_slot_transform(in_item_type)
	return Trs.zero_scale(get_center_position())
