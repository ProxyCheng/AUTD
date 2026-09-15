class_name CrossbowModel
extends TurretModel

# 弩炮表现模型。水平转向 / 俯仰 / 备弹垛的驱动方式见基类 TurretModel;
# 本模型负责弩特有的"弦上箭"表现与骨骼动画采样。
#
# 弩身姿态由 %AnimationPlayer 的关键帧给出,但播放器自带时钟不用:姿态完全由
# backend progress 每帧 seek 采样(见 _on_progress)。
#
# 节点约定(见 crossbow.tscn,相关节点已在场景内标 unique_name_in_owner):
#   base/cog_top/deck/bracket/body → wheel(上弦转轮) / muzzle(弩口)
#   base/cog_top/deck/bracket/body/bone/Skeleton3D/skin → ArrowPointA/B + Arrow

const ANIM_NAME: StringName = &"bone|boneAction_001"

# 备箭垛(基类节点 %AmmoStack,挂在 base/cog_top 下随炮塔水平转向):显示弦下备箭。
# 弦上那支由 %Arrow 负责(仅在非 idle 显示);本垛数量 = bag.count - 1。
# 垛的姿态/几何(item_type、target_length、摆放锚点…)全部在 crossbow.tscn 里配,
# 编辑器里可直观调;ItemStack 自带摆放范围 Gizmo 线框。
# 上弦动作时长(秒):与 backend Crossbow.LOAD_TIME 语义一致——装填期间弦保持松弛。
const NOCK_TIME: float = 0.55
# 弹射动作时长(秒):与 backend Crossbow.FIRE_TIME 一致——松弦沿弩身飞出。
const RELEASE_TIME: float = 0.1
# 上弦转轮(%wheel)满弦时的总转角(圈数)。转角 ∝ progress:随拉弦同步正转。
# 取整圈:松弦后转轮归零与停在原位在视觉上完全一致,故不会有跳变。
const WHEEL_TURNS: float = 2.0

func _ready():
	# 播放器自带时钟不用,姿态完全由 progress 每帧采样决定。
	# 动画约定为单次"满弦→松弦",起点=满弦;换算见 _on_progress。
	var animation: Animation = %AnimationPlayer.get_animation(ANIM_NAME)
	if animation:
		animation.loop_mode = Animation.LOOP_NONE
	# 保持"播放后暂停"的激活态:Godot 只在 active 时按 seek 刷新姿态,stop() 会失效
	%AnimationPlayer.play(ANIM_NAME)
	%AnimationPlayer.pause()
	%AnimationPlayer.seek(%AnimationPlayer.current_animation_length, true)
	# 初始处于 idle(空闲),箭默认隐藏,待 backend 状态落到非 idle 再显示
	%Arrow.visible = false
	# 弦上箭的静止姿态(position/rotation/scale 全量),作为上弦动画的终点 TRS
	_arrow_rest_transform = %Arrow.transform
	_ensure_anchors()
	# 备垛显示数 = 仓存量 - 1:弦上那支由 %Arrow 单独显示(见 count_offset 语义)。
	_ammo_stack.count_offset = 1

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
# 逻辑装填在弦上的箭数(= bag.count);<=0 表示无箭可挂
var _loaded_count: int = 0
# 后端备箭展示仓(由 BuildingActor 经 bind_bag 转发);数量变化驱动箭垛与弦上箭显隐
var _bag: Bag = null
# 上弦动画进行中的时间进度 0..1;-1 表示未在装填
var _nock_t: float = -1.0
# 弹射动画进行中的时间进度 0..1;-1 表示未在弹射
var _release_t: float = -1.0
# 弦上箭静止姿态(skin 局部 TRS);上弦动画的终点
var _arrow_rest_transform: Transform3D = Transform3D.IDENTITY
# 上弦动画起点 TRS(skin 局部)= 备垛最后一支箭的姿态;进入装填后懒计算一次
var _nock_from: Transform3D = Transform3D.IDENTITY
var _nock_from_ready: bool = false

# 状态变化:基类记录阶段并派发动画钩子;弩的"弦上箭显隐"同时依赖 _state 与 bag.count,
# 故这里不做早退,每次调用都补刷一次。
func set_state(in_state: String):
	super(in_state)
	_update_arrow_visibility()

# 进入装填:从备垛最后一支箭拾取→上到弛弦位。弦保持松弛(progress=0),只动箭。
# 起点 TRS 延后到首个 _process 帧再取(垛/骨架的 global 变换需先 refresh 一帧)。
func _on_loading():
	_nock_t = 0.0
	_release_t = -1.0
	_nock_from_ready = false

# 进入弹射:从满弦位沿弩身朝弩口飞出。弦姿态随 progress 松弦,箭走 _process。
func _on_firing():
	_release_t = 0.0
	_nock_t = -1.0

func _on_resting():
	_nock_t = -1.0
	_release_t = -1.0

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

# 归一化 progress → 动画时间:0=松弛(末尾)、1=满弦(起点);并同步箭位与转轮。
func _on_progress(in_progress: float):
	var length: float = %AnimationPlayer.current_animation_length
	_apply_pose((1 - in_progress) * length)
	_update_arrow_position(in_progress)
	_update_wheel(in_progress)

# 箭位置 = 弦位点插值,参数即 progress:满弦(progress=1,弦拉紧)贴 PointB,
# 松弦(progress=0,弦放开)贴 PointA。蓄力 A→B 拉弦,ready 停在 B。
# 装填/弹射阶段由 _process 独立驱动,这里不做 B→A 拖回(否则视觉往回缩)。
func _update_arrow_position(in_progress: float):
	if _state == "loading" or _state == "firing":
		return
	_ensure_anchors()
	var t: float = in_progress if _show_arrow else 0.0
	# 姿态恒为静止 TRS(rotation/scale 不变),只把位置沿弦位点插值
	%Arrow.transform = Transform3D(_arrow_rest_transform.basis, _string_rest_local.lerp(_string_draw_local, t))

# 上弦转轮(%wheel,body 下与骨架平级的刚体件):绕自身 X 轴(= 轮轴)旋转。
# 转角 ∝ progress("弦被拉下的比例"),随拉弦同步正转,满弦停在最大角。
# 纯由 progress 采样、不累积状态,故重绑/回放自洽(无需防补播缓存)。
# 松弦(firing)阶段只放弦、转轮不动:此时 progress 会从 1 回退到 0,
# 若照常跟随会让转轮倒转一圈;因 WHEEL_TURNS 取整圈,随后归零与停在原位视觉一致。
@onready var _wheel: Node3D = %wheel

func _update_wheel(in_progress: float):
	if not _wheel:
		return
	if _state == "firing":
		return
	_wheel.rotation.x = in_progress * WHEEL_TURNS * TAU

func _process(in_delta: float):
	# 装填上弦:整支箭从"备垛最后一支"的 TRS 插值到"弛弦位静止"的 TRS
	# (位置 + 旋转 + 缩放一起过渡,避免只动位置时朝向/大小的突跳)。
	if _state == "loading" and _nock_t >= 0.0:
		if not _nock_from_ready:
			_nock_from = _compute_nock_from()
			_nock_from_ready = true
		_nock_t += in_delta / NOCK_TIME
		var t := clampf(_ease_nock(_nock_t), 0.0, 1.0)
		%Arrow.transform = _nock_from.interpolate_with(_arrow_rest_transform, t)
		if _nock_t >= 1.0:
			_nock_t = -1.0
			%Arrow.transform = _arrow_rest_transform
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

# 上弦起点 TRS(skin 局部):取备垛"最后一支箭"的世界空间 TRS(ItemStack 约定),
# 经"世界 → skin"变换搬到弦上箭的父空间,供与静止 TRS 做整段插值。
# 垛里没有箭(或场景缺节点)时退回静止 TRS,动画退化为原地不动。
func _compute_nock_from() -> Transform3D:
	if not _ammo_stack or not _skin:
		return _arrow_rest_transform
	var src: Variant = _ammo_stack.get_prop_transform(_ammo_stack.visible_count() - 1)
	if not (src is Transform3D):
		return _arrow_rest_transform
	return _skin.global_transform.affine_inverse() * (src as Transform3D)

# 出膛俯仰:用发射器几何(转轴 P + 起点偏移 S,取自 Crossbow)经 Trajectory 求解,
# 保证弩口朝向与箭的抛物线切线一致。
func _aim_pitch(in_center: Vector2, in_aim: Vector2, in_target: Vector2) -> float:
	return Trajectory.aim_pitch_for(in_center, in_aim, in_target,
		Vector2(Crossbow.PIVOT_FORWARD, Crossbow.PIVOT_HEIGHT),
		Vector2(Crossbow.SPAWN_FORWARD, Crossbow.SPAWN_HEIGHT), Crossbow.ARROW_SPEED)

# 绑定后端展示仓:基类把仓转给箭垛;弩另需按 bag.count 判断"弦上是否有箭"(%Arrow 显隐)。
func bind_bag(in_bag: Bag):
	super(in_bag)
	if is_instance_valid(_bag) and _bag.count_changed.is_connected(_on_bag_count_changed):
		_bag.count_changed.disconnect(_on_bag_count_changed)
	_bag = in_bag
	if is_instance_valid(_bag) and not _bag.count_changed.is_connected(_on_bag_count_changed):
		_bag.count_changed.connect(_on_bag_count_changed)
	_on_bag_count_changed()

# bag.count 变化 → 同步"弦上是否有箭"语义(供 %Arrow 显隐)。
func _on_bag_count_changed():
	_loaded_count = _bag.count if is_instance_valid(_bag) else 0
	_update_arrow_visibility()
