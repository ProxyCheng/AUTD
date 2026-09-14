class_name CannonModel
extends TurretModel

# 火炮表现模型。水平转向 / 俯仰 / 备弹垛的驱动方式见基类 TurretModel。
#
# cannon.tscn 是纯刚体模型(无骨骼、无 AnimationPlayer),没有关键帧可播,故开火动画全部
# 由本脚本按 backend 的 state/progress 采样驱动:
#   * 蓄力(charging):引信 %fuse 绕自身 X 轴 0→FUSE_TURN_DEGREES,看起来像引信逐渐烧短;
#   * 开火(firing)  :炮管 %body 沿轴缩短、截面变粗,再弹回,读作把炮弹使劲挤出去;
#   * 装填(loading) :换新引信(引信归零)并复位炮管。
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

# 炮管形变进度:1=刚开火(形变最大),0=已复原;负值表示当前未在形变。
var _recoil_t: float = -1.0

# 出膛俯仰:起点几何沿用 Crossbow 的静态值,弹速取 Cannon.PROJECTILE_SPEED
# (backend 单一事实来源,前端不另存一份),与 backend Cannon.fire() 共用 Arrow.aim_pitch_for。
func _aim_pitch(in_center: Vector2, in_aim: Vector2, in_target: Vector2) -> float:
	return Arrow.aim_pitch_for(in_center, in_aim, in_target,
		Vector2(Crossbow.PIVOT_FORWARD, Crossbow.PIVOT_HEIGHT),
		Vector2(Crossbow.SPAWN_FORWARD, Crossbow.SPAWN_HEIGHT), Cannon.PROJECTILE_SPEED)

# 同状态重复调用直接早退:重绑进开火态时不重播形变(引信/炮管保持当前姿态)。
func set_state(in_state: String):
	if in_state == _state:
		return
	super(in_state)

func _on_loading():
	%fuse.rotation_degrees.x = 0.0
	_reset_barrel()

func _on_firing():
	# 引信烧到底(重绑进入开火态时也自洽,不依赖 progress 是否变化过)
	%fuse.rotation_degrees.x = FUSE_TURN_DEGREES
	_recoil_t = 1.0

func _on_resting():
	_reset_barrel()

# 蓄力进度驱动引信烧短。开火/装填阶段的引信由状态钩子管理,这里不跟(避免"回卷")。
func _on_progress(in_progress: float):
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
