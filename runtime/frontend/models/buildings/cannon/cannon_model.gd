class_name CannonModel
extends Node3D

# 火炮表现模型:水平转向与俯仰的驱动方式与弩炮一致(读 backend 的 aim_direction + 目标位置),
# 但 cannon.tscn 是纯刚体模型(无骨骼、无 AnimationPlayer),故蓄力/开火没有专门动画:
# 蓄力进度由建筑头顶的 work_progress 条呈现,本模型只负责炮塔转向、炮身俯仰与备弹垛。
#
# 节点约定(见 cannon.tscn,节点均已在场景内标 unique_name_in_owner):
#   base(FBX 内 rotX=-90°、scale=100) → cog_left / cog_right / cog_top
#   cog_top → deck/bracket/body(俯仰),cog_top → AmmoStack(备弹垛,随炮塔转向)

# 炮身仰角与 body.rotation.x 成 1:1 线性但符号相反:要炮口对齐弹道切线 pitch,
# 取 body.rotation.x = -pitch + BARREL_REST_ELEVATION。static var 便于在场景里实时试参。
static var BARREL_REST_ELEVATION: float = 0.261799  # 弧度(= 15°)

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

# —— 备弹垛(%AmmoStack,挂 base/cog_top 下,随炮塔转向)——
@onready var _ammo_stack: ItemStack = %AmmoStack

# 绑定后端展示仓(由 BuildingActor 转发):垛跟随 Bag 的 item_type/count 显示备弹。
func bind_bag(in_bag: Bag):
	if _ammo_stack:
		_ammo_stack.bind(in_bag)
