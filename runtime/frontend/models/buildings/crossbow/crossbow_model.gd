class_name CrossbowModel
extends Node3D

const ANIM_NAME: StringName = &"bone|boneAction_001"

# 备箭垛:显示在炮塔平台(随 %cog_top 水平转向)上的备用弩箭。
# 弦上那支由 %Arrow 负责(仅在非 idle 显示),本垛展示"弦下"的备箭。
# 数量 = backend 转发的 stored_count - 1(弦上已占一支)。几何由 ItemStack 组件渲染(3×3=9 封顶)。
# 备箭垛在"模型真实单位(根空间)"下的落点锚点(垛底面中心)。
# 实测:八角形平台板(deck)顶面 y≈0.424,x∈[-0.386,0.388], z∈[-0.364,0.414];
# 中央机构(bracket)占 x∈[-0.155,0.165], z∈[-0.05,0.28],故净空区为后部( z<0 )。
# 锚点取平台面(y=0.424)后部右侧净空:整垛底边贴平台,避开中央机构。常量可微调。
const AMMO_ANCHOR: Vector3 = Vector3(0.22, 0.424, -0.20)

# 上弦动作时长(秒):与 backend Crossbow.LOAD_TIME 语义一致——装填期间弦保持松弛。
const NOCK_TIME: float = 0.55
# 弹射动作时长(秒):与 backend Crossbow.FIRE_TIME 一致——松弦沿弩身飞出。
const RELEASE_TIME: float = 0.1

func _ready():
	# 播放器自带时钟不用,姿态完全由 progress 每帧采样决定。
	# 动画约定为单次"满弦→松弦",起点=满弦;换算见 set_progress。
	var animation: Animation = %AnimationPlayer.get_animation(ANIM_NAME)
	if animation:
		animation.loop_mode = Animation.LOOP_NONE
	# 保持"播放后暂停"的激活态:Godot 只在 active 时按 seek 刷新姿态,stop() 会失效
	%AnimationPlayer.play(ANIM_NAME)
	%AnimationPlayer.pause()
	%AnimationPlayer.seek(%AnimationPlayer.current_animation_length, true)
	# 初始处于 idle(空闲),箭默认隐藏,待 backend 状态落到非 idle 再显示
	%Arrow.visible = false
	_build_ammo_stack()
	_ensure_anchors()

# ---------------------------------------------------------------- #
# 动画关键锚点(skin 局部坐标,即 %Arrow 的父空间)
#   弛弦位(上弦终点)   : ArrowPointA
#   满弦位(拉满起点)   : ArrowPointB
#   弹射出口(弩口方向) : 由 muzzle 世界位置换算到 skin 局部(懒计算)
#   装填拾取点(备垛顶) : 由 _ammo_stack 顶箭换算到 skin 局部(懒计算)
# %Arrow 是 skin 的子节点,故所有 lerp 都在 skin 局部坐标做,规避骨架/皮肤变换。
# 静态锚点(弛/满弦位)直接读节点 position,不依赖 global;弩口方向在首次用时
# 才换算(global_transform 需场景树先 refresh 一帧,首个 _ready 阶段不稳)。
# ---------------------------------------------------------------- #
const SKIN_PATH: String = "base/cog_top/deck/bracket/body/bone/Skeleton3D/skin"
const MUZZLE_PATH: String = "base/cog_top/deck/bracket/body/muzzle"

var _skin: Node3D = null
var _muzzle: Node3D = null
var _string_rest_local: Vector3 = Vector3.ZERO   # 上弦终点(=ArrowPointA.position)
var _string_draw_local: Vector3 = Vector3.ZERO   # 满弦位(=ArrowPointB.position)
var _fwd_local: Vector3 = Vector3.ZERO           # 弹射前进方向(skin 局部,单位向量)
var _muzzle_exit_local: Vector3 = Vector3.ZERO   # 弹射出口 = 满弦位 + 前进方向若干
var _dir_ready: bool = false                     # 弩口方向是否已换算(global 已 refresh)
var _anchors_ready: bool = false                 # 静态弦位是否已解析(_ready 可能被前置动画初始化中断)

func _ensure_anchors():
	# 幂等:静态弦位已解析则跳过。
	if _anchors_ready:
		return
	# 显式路径取 skin/muzzle(不依赖 owner 的 % 语义),最稳。
	var s: Node3D = get_node_or_null(SKIN_PATH)
	if s:
		_skin = s
	var m: Node3D = get_node_or_null(MUZZLE_PATH)
	_muzzle = m if m else _skin
	# 静态弦位:直接读节点 position,不依赖 global_transform。
	_string_rest_local = _string_rest_local_for()
	_string_draw_local = _string_draw_local_for()
	_anchors_ready = true
	# 弩口方向(依赖 global_transform)延后到首次 nock/release 前换算。
	_dir_ready = false

func _string_rest_local_for() -> Vector3:
	var a: Node3D = get_node_or_null(SKIN_PATH + "/ArrowPointA")
	return a.position if a else Vector3.ZERO

func _string_draw_local_for() -> Vector3:
	var b: Node3D = get_node_or_null(SKIN_PATH + "/ArrowPointB")
	return b.position if b else Vector3.ZERO

# 懒换算弩口方向/出口:首次装填或弹射前调用(此时场景树已 refresh,global 有效)。
func _ensure_direction():
	_ensure_anchors()
	if _dir_ready:
		return
	if not _skin or not _muzzle or _muzzle == _skin:
		# 兜底:沿用静态弦位附近,避免零向量
		_fwd_local = Vector3.FORWARD
		_muzzle_exit_local = _string_draw_local + _fwd_local * 0.25
		_dir_ready = true
		return
	var muzzle_world: Vector3 = _muzzle.global_transform.origin
	var draw_local := _string_draw_local
	_fwd_local = (_skin.to_local(muzzle_world) - draw_local).normalized()
	_muzzle_exit_local = _skin.to_local(muzzle_world) + _fwd_local * 0.25
	_dir_ready = true

# 蓄力/待发/射击期间显示箭;仅 idle(空闲)隐藏。
# 弦上箭必须在"真的有一发装填"时才显示:非 idle 且备箭存量 > 0。
var _show_arrow: bool = false
# 当前后端阶段(idle/loading/charging/ready/firing),由 set_state 记录
var _state: String = "idle"
# 逻辑装填在弦上的箭数(= stored_count);<=0 表示无箭可挂
var _loaded_count: int = 0
# 上弦动画进行中的时间进度 0..1;-1 表示未在装填
var _nock_t: float = -1.0
# 弹射动画进行中的时间进度 0..1;-1 表示未在弹射
var _release_t: float = -1.0

func set_state(in_state: String):
	_state = in_state
	match in_state:
		"loading":
			# 进入装填:从备垛顶拾取→上到弛弦位。弦保持松弛(progress=0),只动箭。
			_nock_t = 0.0
			_release_t = -1.0
		"firing":
			# 进入弹射:从满弦位沿弩身朝弩口飞出。弦姿态随 progress 松弦,箭走 _process。
			_release_t = 0.0
			_nock_t = -1.0
		_:
			_nock_t = -1.0
			_release_t = -1.0
	_update_arrow_visibility()

func _update_arrow_visibility():
	# 弦上箭 = 弦上有货(非 idle)且弹药仓还有一支真正的主力;
	# 例外:弹射(firing)阶段即使这已是最后一支(loaded_count 将随 removed_count 归零),
	# 弦上这支也应可见——它正是正要被射出的那支。故 firing 恒可见(只要非 idle)。
	_show_arrow = _state != "idle" and (_state == "firing" or _loaded_count > 0)
	%Arrow.visible = _show_arrow

func _apply_pose(in_time: float):
	# seek 需要激活态才刷新关键帧姿态:暂停中先 play 再 seek 再暂停
	if not %AnimationPlayer.is_playing():
		%AnimationPlayer.play(ANIM_NAME)
	%AnimationPlayer.seek(in_time, true)
	%AnimationPlayer.pause()

func set_progress(in_progress: float):
	# 归一化 progress → 动画时间:0=松弛(末尾)、1=满弦(起点)。
	var length: float = %AnimationPlayer.current_animation_length
	_apply_pose((1 - in_progress) * length)
	_update_arrow_position(in_progress)

# 箭位置 = 弦位点插值,参数即 progress:满弦(progress=1,弦拉紧)贴 PointB,
# 松弦(progress=0,弦放开)贴 PointA。蓄力 A→B 拉弦,ready 停在 B。
# 装填/弹射阶段由 _process 独立驱动,这里不做 B→A 拖回(否则视觉往回缩)。
func _update_arrow_position(in_progress: float):
	if _state == "loading" or _state == "firing":
		return
	_ensure_anchors()
	var t: float = in_progress if _show_arrow else 0.0
	%Arrow.position = _string_rest_local.lerp(_string_draw_local, t)

func _process(in_delta: float):
	# 装填上弦:从拾取点 → 弛弦位,弦保持松弛。
	if _state == "loading" and _nock_t >= 0.0:
		_ensure_direction()
		_nock_t += in_delta / NOCK_TIME
		var t := clampf(_ease_nock(_nock_t), 0.0, 1.0)
		%Arrow.position = _pickup_skin_local().lerp(_string_rest_local, t)
		if _nock_t >= 1.0:
			_nock_t = -1.0
			%Arrow.position = _string_rest_local
		return
	# 弹射:从满弦位沿弩身朝弩口加速飞出(离心),不再被弦拖回 A。
	if _state == "firing" and _release_t >= 0.0:
		_ensure_direction()
		_release_t += in_delta / RELEASE_TIME
		var t := clampf(_ease_release(_release_t), 0.0, 1.0)
		%Arrow.visible = false
		%Arrow.position = _string_draw_local.lerp(_muzzle_exit_local, t)
		if _release_t >= 1.0:
			_release_t = -1.0

# 上弦缓动:慢起快收,像被手端上去而非瞬移
func _ease_nock(in_t: float) -> float:
	return in_t * in_t * (3.0 - 2.0 * in_t)

# 弹射缓动:起手快、越飞越快(离弦瞬间加速),用平方加速
func _ease_release(in_t: float) -> float:
	return in_t * in_t

var _pickup_local: Vector3 = Vector3.ZERO
var _pickup_computed: bool = false

# 取备垛顶那支可抓取的箭的 global 位置,换算到 skin 局部作为拾取起点。
func _pickup_skin_local() -> Vector3:
	if not _pickup_computed:
		var grab_world := _ammo_stack_top_world()
		_pickup_local = _skin.to_local(grab_world) if _skin else _string_rest_local
		_pickup_computed = true
	return _pickup_local

func _ammo_stack_top_world() -> Vector3:
	if not _ammo_stack:
		return _string_rest_local
	# 垛内最高(最上层)可见箭的 global 位置:取可见 prop 里 y 最大者,近似"顶部可抓取那支"。
	var top: Vector3 = _ammo_stack.global_position + Vector3(0, 0.15, 0)
	var found := false
	for prop in _ammo_stack.find_children("", "Node3D", true, false):
		if not (prop is Node3D):
			continue
		var p3: Node3D = prop
		if not p3.visible:
			continue
		if not found or p3.global_position.y > top.y:
			top = p3.global_position
			found = true
	return top

# 当前累计水平朝向角(弧度,不 wrap),跨 ±π 边界时靠 wrapf 平滑推进,避免 cog 部件瞬间反转。
var _current_yaw: float = 0.0

# 炮口水平朝向:由 backend 传入的 aim_direction(单位向量,y 为世界 z)决定。
# backend 已做限速,方向向量是逐帧连续变化的;这里把它累计成连续角度(不跳变)。
func set_aim_direction(in_direction: Vector3):
	# 模型 rest 朝 +Z(= Vector3.BACK),故取 atan2(x, z) 为朝向角
	var target_angle: float = atan2(in_direction.x, in_direction.z)
	var delta: float = wrapf(target_angle - _current_yaw, -PI, PI)
	_current_yaw += delta
	%cog_top.rotation.z = _current_yaw
	%cog_left.rotation.x = _current_yaw * 8 / 5
	%cog_right.rotation.x = -_current_yaw * 8 / 5

# 仅按目标距离调整俯仰;水平朝向改走 set_aim_direction。
func set_target_position(in_position: Vector3):
	var distance: float = global_position.distance_squared_to(in_position)
	var max_angle: float = 40 * PI / 180
	%body.rotation.x = max_angle * (1 - (distance - 1) / 5)

# —— 备箭垛(挂 %cog_top,随炮塔转向) ——

# ItemStack 组件实例
var _ammo_stack: ItemStack = null

# 在 %cog_top 下建备箭垛。%cog_top 深在 FBX 导入层(base 含 40 缩放 + 旋转),
# 直接用 root 空间的真实锚点经 base 逆变换写入其本地 transform,
# 使垛内以真实尺寸落在甲板顶面,并随炮塔水平转向。
func _build_ammo_stack():
	var cog_top: Node3D = %cog_top
	_ammo_stack = ItemStack.new()
	_ammo_stack.name = "AmmoStack"
	# 配置几何:3 支×3 层 = 9 支封顶;箭长轴略小,平放同向逐层摞
	_ammo_stack.per_row = 3
	_ammo_stack.layer_count = 3
	_ammo_stack.target_length = 0.35
	_ammo_stack.row_spacing = 1.05
	_ammo_stack.layer_spacing = 1.2
	# %cog_top 的父链是 root → base → cog_top(FBX 导入 base 含 40 缩放 + 旋转)。
	var base: Node3D = get_node("base")
	var cog_top_local: Node3D = %cog_top
	var head: Transform3D = base.transform * cog_top_local.transform
	var real_anchor := Transform3D(Basis.IDENTITY, AMMO_ANCHOR)
	_ammo_stack.transform = head.affine_inverse() * real_anchor
	cog_top.add_child(_ammo_stack)
	_ammo_stack.set_item_type("arrow")
	_ammo_stack.set_count(0)

# BuildingActor 转发存量变化:备箭数 = stored_count - 1(弦上那支由 %Arrow 显示),
# 下限 0,上限 AMMO_STACK_SIZE。in_capacity 仅作镜像展示用,本模型按 9 封顶内部截断。
func set_stored_count(in_count: int, _in_capacity: int):
	_loaded_count = in_count
	if _ammo_stack:
		_ammo_stack.set_count(maxi(in_count - 1, 0))
	_update_arrow_visibility()
	# 存量变化可能会重置拾取点(垛顶箭变了),但上弦中途不必重算,保持一次连贯即可
