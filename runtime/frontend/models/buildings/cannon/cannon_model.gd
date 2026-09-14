class_name CannonModel
extends Node3D

# 火炮表现模型:水平转向与俯仰的驱动方式与弩炮一致(读 backend 的 aim_direction + 目标位置)。
# cannon.tscn 是纯刚体模型(无骨骼、无 AnimationPlayer),没有关键帧可播,故开火动画全部
# 由本脚本按 backend 的 state/progress 采样驱动:
#   * 蓄力(charging):引信 %fuse 绕自身 X 轴 0→FUSE_TURN_DEGREES,看起来像引信逐渐烧短;
#   * 开火(firing)  :炮管 %body 沿轴缩短、截面变粗,再弹回,读作把炮弹使劲挤出去;
#   * 装填(loading) :换新引信(引信归零)并复位炮管。
# 蓄力数值本身仍由建筑头顶的 work_progress 条呈现。
#
# 节点约定(见 cannon.tscn,相关节点已在场景内标 unique_name_in_owner):
#   base(FBX 内 rotX=-90°;场景覆写 scale=40,与弩炮一致) → cog_left / cog_right / cog_top
#   cog_top → deck/bracket/body(俯仰),cog_top → AmmoStack(备弹垛,随炮塔转向)
#   body → fuse(引信)

# 炮身仰角与 body.rotation.x 成 1:1 线性但符号相反:要炮口对齐弹道切线 pitch,
# 取 body.rotation.x = -pitch + BARREL_REST_ELEVATION。static var 便于在场景里实时试参。
static var BARREL_REST_ELEVATION: float = 0.261799  # 弧度(= 15°)

# —— 开火动画参数(纯表现,可直接调)——
# 引信绕自身 X 轴的总转角(度):随蓄力进度 0→本值,读作引信逐渐烧短。
const FUSE_TURN_DEGREES: float = 32.0
# 开火瞬间炮管形变幅度:沿炮管轴缩短、截面变粗(近似体积守恒),随后弹回。
const RECOIL_SQUASH: float = 0.12
# 炮管形变回弹时长(秒),与 backend Cannon.FIRE_TIME 一致(开火态持续时长)。
const RECOIL_TIME: float = 0.2

# 当前累计水平朝向角(弧度,不 wrap):跨 ±π 边界时靠 wrapf 平滑推进,避免齿轮部件瞬间反转。
var _current_yaw: float = 0.0
# 世界 XZ 单位朝向向量(与 backend aim_direction 同);用于推算与 fire() 一致的出膛俯仰。
var _aim_dir: Vector3 = Vector3.FORWARD

# 炮口水平朝向:由 backend 传入的 aim_direction(单位向量,y 为世界 z)决定。
# backend 已做限速,方向向量逐帧连续变化;这里累计成连续角度,不跳变。
func set_aim_direction(in_direction: Vector3):
	_aim_dir = in_direction
	# 模型 rest 朝 +Z(= Vector3.BACK),故取 atan2(x, z) 为朝向角
	var target_angle: float = atan2(in_direction.x, in_direction.z)
	var delta: float = wrapf(target_angle - _current_yaw, -PI, PI)
	_current_yaw += delta
	%cog_top.rotation.z = _current_yaw
	%cog_left.rotation.x = _current_yaw * 8 / 5
	%cog_right.rotation.x = -_current_yaw * 8 / 5

# 俯仰对齐炮弹离弦瞬间的抛物线切线,使炮弹"顺膛而出"。
# 求解与 backend Cannon.fire() 共用 Arrow.aim_pitch_for:几何沿用 Crossbow 的静态值,
# 弹速取 Cannon.PROJECTILE_SPEED(backend 单一事实来源,前端不另存一份)。
func set_target_position(in_position: Vector3):
	var center := Vector2(global_position.x, global_position.z)
	var aim := Vector2(_aim_dir.x, _aim_dir.z)
	if aim == Vector2.ZERO:
		return
	var pitch: float = Arrow.aim_pitch_for(center, aim, Vector2(in_position.x, in_position.z),
		Vector2(Crossbow.PIVOT_FORWARD, Crossbow.PIVOT_HEIGHT),
		Vector2(Crossbow.SPAWN_FORWARD, Crossbow.SPAWN_HEIGHT), Cannon.PROJECTILE_SPEED)
	%body.rotation.x = -pitch + BARREL_REST_ELEVATION

# —— 开火动画(state/progress 驱动,无 AnimationPlayer)——

# 当前 backend 阶段(idle/loading/charging/ready/firing),由 set_state 记录。
var _state: String = ""
# 炮管形变进度:1=刚开火(形变最大),0=已复原;负值表示当前未在形变。
var _recoil_t: float = -1.0

# 状态变化:进装填换新引信并复位炮管;进开火起振炮管形变(由 _process 衰减回弹)。
func set_state(in_state: String):
	if in_state == _state:
		return
	_state = in_state
	match in_state:
		"loading":
			%fuse.rotation_degrees.x = 0.0
			_reset_barrel()
		"firing":
			# 引信烧到底(重绑进入开火态时也自洽,不依赖 progress 是否变化过)
			%fuse.rotation_degrees.x = FUSE_TURN_DEGREES
			_recoil_t = 1.0
		_:
			_reset_barrel()

# 蓄力进度驱动引信烧短。开火/装填阶段的引信由 set_state 管理,这里不跟(避免"回卷")。
func set_progress(in_progress: float):
	if _state == "loading" or _state == "firing":
		return
	%fuse.rotation_degrees.x = in_progress * FUSE_TURN_DEGREES

func _process(in_delta: float):
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

# —— 备弹垛(%AmmoStack,挂 base/cog_top 下,随炮塔转向)——
@onready var _ammo_stack: ItemStack = %AmmoStack

# 绑定后端展示仓(由 BuildingActor 转发):垛跟随 Bag 的 item_type/count 显示备弹。
func bind_bag(in_bag: Bag):
	if _ammo_stack:
		_ammo_stack.bind(in_bag)
