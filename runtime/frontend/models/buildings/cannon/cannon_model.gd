class_name CannonModel
extends TurretModel

# 火炮表现模型。水平转向 / 俯仰 / 备弹垛的驱动方式见基类 TurretModel。
#
# cannon.tscn 是纯刚体模型(无骨骼、无 AnimationPlayer),没有关键帧可播,故开火/装填动画
# 全部由本脚本按 backend 的 state/progress 采样驱动:
#   * 蓄力(charging):引信 %fuse 绕自身 X 轴 0→FUSE_TURN_DEGREES,看起来像引信逐渐烧短;
#   * 开火(firing)  :炮管 %body 沿轴缩短、截面变粗,再弹回,读作把炮弹使劲挤出去;
#   * 装填(loading) :炮筒先俯仰到竖直,炮弹从备弹垛沿倒 U 轨迹飞入炮口,再俯仰回瞄准角。
# 蓄力数值本身仍由建筑头顶的 work_progress 条呈现。
#
# 本模型特有节点:cog_top → deck/bracket/body(俯仰),body → fuse(引信)。

# —— 开火动画参数(纯表现,可直接调)——
# 引信绕自身 X 轴的总转角(度):随蓄力进度 0→本值,读作引信逐渐烧短。
const FUSE_TURN_DEGREES: float = 32.0
# 开火瞬间炮管形变幅度:沿炮管轴缩短、截面变粗(近似体积守恒),随后弹回。
const RECOIL_SQUASH: float = 0.12
# 炮管形变回弹时长(秒),与 backend Cannon.FIRE_TIME 一致(开火态持续时长)。
const RECOIL_TIME: float = 0.2

# —— 装填动画参数(纯表现,可直接调)——
# 整段装填动画时长(秒),与 backend Cannon.CANNON_LOAD_TIME 同步(loading 态持续时长)。
const LOAD_ANIM_TIME: float = 1.2
# 三段时长占比(0..1,累加为 1):抬炮筒 → 炮弹飞入 → 炮筒回摆。
const LOAD_ROTATE_UP_END: float = 0.30
const LOAD_BALL_FLIGHT_END: float = 0.75
# 炮口竖直时的 body.rotation.x:炮口仰角 = -body.rotation.x,竖直向上即仰角 +90°。
const VERTICAL_PITCH: float = -PI * 0.5
# 炮弹倒 U 轨迹的拱高系数:顶点抬升 = 起终点直线距离 × 本值。
const LOAD_BALL_ARC_RATIO: float = 0.55
# 装填炮弹表现节点用的场景(与 backend 弹丸同款);尺寸在运行时对齐备弹垛。
const LOAD_BALL_SCENE: String = "res://runtime/frontend/models/entities/cannonball/cannonball.tscn"

# 炮管形变进度:1=刚开火(形变最大),0=已复原;负值表示当前未在形变。
var _recoil_t: float = -1.0

# 装填动画进度 0..1;-1 表示未在装填。
var _load_t: float = -1.0
# 进入装填时炮筒的 body.rotation.x,作为回摆终点(装填结束后交还瞄准驱动)。
var _load_start_pitch: float = 0.0
# 飞入炮口的炮弹表现节点(常驻、按需显隐),与备弹垛同款同尺寸。
var _load_ball: Node3D = null
# 炮弹起飞点(世界坐标):进入飞行段首帧从备弹垛顶取一次,之后不再跟随垛。
var _load_ball_from_world: Vector3 = Vector3.ZERO
var _load_ball_from_ready: bool = false

# 引信冒烟发射器(嵌在 %fuse 下,随引信一起旋转)。
@onready var _fume: GPUParticles3D = %fume

func _ready():
	_load_ball = _make_load_ball()

# 出膛俯仰:起点几何沿用 Turret 的静态值,弹速取 Cannon.PROJECTILE_SPEED
# (backend 单一事实来源,前端不另存一份),经 Trajectory 求解。
func _aim_pitch(in_center: Vector2, in_aim: Vector2, in_target: Vector2) -> float:
	return Trajectory.aim_pitch_for(in_center, in_aim, in_target,
		Vector2(Turret.PIVOT_FORWARD, Turret.PIVOT_HEIGHT),
		Vector2(Turret.SPAWN_FORWARD, Turret.SPAWN_HEIGHT), Cannon.PROJECTILE_SPEED)

# 同状态重复调用直接早退:重绑进开火态时不重播形变(引信/炮管保持当前姿态)。
func set_state(in_state: String):
	if in_state == _state:
		return
	super(in_state)
	_apply_fume()

# 引信冒烟:只在引信点燃的阶段(蓄力/开火)喷烟。ready 是引信已烧到底的静置态,
# 不冒烟;idle/loading 引信未点燃,同样熄火。
func _apply_fume():
	if not _fume:
		return
	_fume.emitting = _state in ["charging", "firing"]

# 装填期间炮筒由装填动画独占,忽略瞄准俯仰(BuildingActor 每帧仍会转发目标位置)。
# 装填结束交还给基类,瞄准驱动自动接管。
func set_target_position(in_position: Vector3):
	if _state == "loading":
		return
	super(in_position)

func _on_loading():
	%fuse.rotation_degrees.x = 0.0
	_reset_barrel()
	# 从当前俯仰起摆,回摆时回到同一角度,避免装填前后姿态跳变。
	_load_start_pitch = %body.rotation.x
	_load_t = 0.0
	_load_ball_from_ready = false
	_show_load_ball(false)

func _on_firing():
	# 引信烧到底(重绑进入开火态时也自洽,不依赖 progress 是否变化过)
	%fuse.rotation_degrees.x = FUSE_TURN_DEGREES
	_recoil_t = 1.0
	_load_t = -1.0
	_show_load_ball(false)

func _on_resting():
	_reset_barrel()
	_load_t = -1.0
	_show_load_ball(false)

# 蓄力进度驱动引信烧短。开火/装填阶段的引信由状态钩子管理,这里不跟(避免"回卷")。
func _on_progress(in_progress: float):
	if _state == "loading" or _state == "firing":
		return
	%fuse.rotation_degrees.x = in_progress * FUSE_TURN_DEGREES

func _process(in_delta: float):
	_tick_recoil(in_delta)
	_tick_loading(in_delta)

# —— 开火形变 ——

func _tick_recoil(in_delta: float):
	if _recoil_t < 0.0:
		return
	_recoil_t = maxf(_recoil_t - in_delta / RECOIL_TIME, 0.0)
	_apply_barrel_squash(_recoil_t)
	if _recoil_t <= 0.0:
		_recoil_t = -1.0

# 炮管形变:炮管轴 = body 局部 Y,故缩短 Y、加粗 XZ(近似体积守恒,读作把炮弹挤出去)。
func _apply_barrel_squash(in_amount: float):
	%body.scale = Vector3(
		1.0 + RECOIL_SQUASH * in_amount,
		1.0 - RECOIL_SQUASH * in_amount,
		1.0 + RECOIL_SQUASH * in_amount)

func _reset_barrel():
	_recoil_t = -1.0
	%body.scale = Vector3.ONE

# —— 装填动画 ——

# 三段推进:炮筒抬到竖直 → 炮弹倒 U 飞入 → 炮筒回摆到进入时的俯仰。
func _tick_loading(in_delta: float):
	if _state != "loading" or _load_t < 0.0:
		return
	_load_t = minf(_load_t + in_delta / LOAD_ANIM_TIME, 1.0)
	var t: float = _load_t
	if t < LOAD_ROTATE_UP_END:
		%body.rotation.x = lerpf(_load_start_pitch, VERTICAL_PITCH, _ease(t / LOAD_ROTATE_UP_END))
		_show_load_ball(false)
	elif t < LOAD_BALL_FLIGHT_END:
		# 炮筒保持竖直,炮弹从垛顶沿倒 U 抛物线飞向炮口。
		%body.rotation.x = VERTICAL_PITCH
		_tick_load_ball((t - LOAD_ROTATE_UP_END) / (LOAD_BALL_FLIGHT_END - LOAD_ROTATE_UP_END))
	else:
		_show_load_ball(false)
		%body.rotation.x = lerpf(VERTICAL_PITCH, _load_start_pitch, _ease((t - LOAD_BALL_FLIGHT_END) / (1.0 - LOAD_BALL_FLIGHT_END)))
	if t >= 1.0:
		_load_t = -1.0
		%body.rotation.x = _load_start_pitch

# 炮弹位置:起点(垛顶)与终点(炮口)都换算到模型根局部系插值;局部 y 即世界竖直方向
# (模型根只随 actor 绕 y 转向),故直接在 y 上叠倒 U 拱高即可。
func _tick_load_ball(in_k: float):
	if not _load_ball:
		return
	if not _load_ball_from_ready:
		_load_ball_from_world = _ammo_top_world()
		_load_ball_from_ready = true
	var from_local: Vector3 = to_local(_load_ball_from_world)
	var to_local_pos: Vector3 = to_local(_muzzle_world())
	var arc: float = from_local.distance_to(to_local_pos) * LOAD_BALL_ARC_RATIO
	var pos: Vector3 = from_local.lerp(to_local_pos, in_k)
	pos.y += 4.0 * arc * in_k * (1.0 - in_k)
	_load_ball.position = pos
	_show_load_ball(true)

# 炮口入膛点(世界坐标):炮筒 Mesh 的局部 AABB 沿炮管轴(-Y)最外端中心;
# body 已被装填动画摆到竖直,故该点即当前炮口顶端。
func _muzzle_world() -> Vector3:
	var mesh := %body as MeshInstance3D
	if not mesh:
		return %body.global_position
	var box: AABB = mesh.get_aabb()
	return mesh.to_global(Vector3(0.0, box.position.y, 0.0))

# 装填炮弹的起飞点(世界坐标):垛在进入装填时已按"武器内一发"少显示一支,
# 故优先取 ItemStack 记录的"刚被取走那支"的当前世界 TRS(实时换算,垛转向后仍正确);
# 无记录(如模型刚绑定)时退回垛顶可见的那支。
func _ammo_top_world() -> Vector3:
	if _ammo_stack:
		var taken: Variant = _ammo_stack.last_removed_transform()
		if taken is Transform3D:
			return (taken as Transform3D).origin
		var count: int = _ammo_stack.visible_count()
		if count > 0:
			var tr: Variant = _ammo_stack.get_prop_transform(count - 1)
			if tr is Transform3D:
				return (tr as Transform3D).origin
		return _ammo_stack.global_position
	return global_position

func _show_load_ball(in_visible: bool):
	if _load_ball:
		_load_ball.visible = in_visible

# 建装填炮弹节点(模型根子节点):与备弹垛同款场景,尺寸对齐垛内道具
# (逐级相乘局部 scale,避免依赖尚未 refresh 的 global 变换)。
func _make_load_ball() -> Node3D:
	var scene: PackedScene = load(LOAD_BALL_SCENE)
	if not scene:
		return null
	var ball: Node3D = scene.instantiate()
	ball.name = "LoadBall"
	ball.visible = false
	add_child(ball)
	ball.scale = Vector3.ONE * _ammo_stack_scale()
	return ball

func _ammo_stack_scale() -> float:
	var s: float = 1.0
	var node: Node = _ammo_stack
	while node and node != self:
		if node is Node3D:
			s *= (node as Node3D).scale.x
		node = node.get_parent()
	return s

# 平滑缓动(smoothstep):起止都减速,读作机械臂而非瞬移。
func _ease(in_t: float) -> float:
	return in_t * in_t * (3.0 - 2.0 * in_t)
