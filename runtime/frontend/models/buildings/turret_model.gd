@abstract
class_name TurretModel
extends Node3D

# 炮塔类建筑模型的共用基类:弩炮(crossbow)与火炮(cannon)的节点结构与驱动方式一致
# (base → cog_left/cog_right/cog_top 齿轮组 → body 俯仰),故把共用部分收在这里:
#   * 水平转向:aim_direction → cog_top 转角,两侧齿轮按 COG_TURN_RATIO 联动;
#   * 俯仰    :目标位置 → 弹道切线 pitch → body.rotation.x(弹道几何由子类提供);
#   * 备弹垛  :%AmmoStack 绑定后端展示仓;
#   * 状态机  :set_state/set_progress 派发到子类钩子。
# 子类只需给出自己的弹道求解与各状态的动画钩子;子类特有的节点(弩的弦/箭、
# 炮的引信)与其动画时序仍归子类。
#
# 节点约定(两个模型场景都已在 .tscn 里标 unique_name_in_owner):
#   base(FBX 内 rotX=-90°;场景覆写 scale=40) → cog_left / cog_right / cog_top
#   cog_top → deck/bracket/body(俯仰),cog_top → AmmoStack(备弹垛,随炮塔水平转向)

# 两侧齿轮相对炮塔水平转向的放大倍率(齿轮自转角 = 转向角 × 本值)。
# 取 8/5 而非整数,让齿轮转速与炮塔转向拉开区别,读数更"机械"。
const COG_TURN_RATIO: float = 8.0 / 5.0

# 当前累计水平朝向角(弧度,不 wrap):跨 ±π 边界时靠 wrapf 平滑推进,避免齿轮部件瞬间反转。
var _current_yaw: float = 0.0
# 世界 XZ 单位朝向向量(与 backend aim_direction 同);用于推算与 backend fire() 一致的出膛俯仰。
var _aim_dir: Vector3 = Vector3.FORWARD
# 当前后端阶段(idle/loading/charging/ready/firing),由 set_state 记录。初值取 backend 的初始态。
var _state: String = "idle"
# 最近一次 backend 上弦/装弹进度([0,1],见 set_load_progress):loading 阶段的表现按它采样。
var _load_progress: float = 0.0

# —— 水平转向 ——

# 炮口水平朝向:由 backend 传入的 aim_direction(单位向量,y 为世界 z)决定。
# backend 已做限速,方向向量逐帧连续变化;这里累计成连续角度,不跳变。
#
# in_direction 是世界空间向量,而 %cog_top.rotation.z 是局部角:BuildingActor 会按建筑
# direction 对整个模型 look_at(见 BuildingActor._on_direction_changed),模型局部系已随
# 建筑旋转。若直接拿世界 yaw 赋给局部角,建筑朝向会被重复计入一次 —— 建筑每转 90°,
# 炮塔就整体偏 90°。故先经本节点 global_transform 反解回局部系再取角。
func set_aim_direction(in_direction: Vector3):
	_aim_dir = in_direction
	var local_direction: Vector3 = global_transform.basis.inverse() * in_direction
	# 模型 rest 朝 +Z(= Vector3.BACK),故取 atan2(x, z) 为朝向角
	var target_angle: float = atan2(local_direction.x, local_direction.z)
	var delta: float = wrapf(target_angle - _current_yaw, -PI, PI)
	_current_yaw += delta
	%cog_top.rotation.z = _current_yaw
	%cog_left.rotation.x = _current_yaw * COG_TURN_RATIO
	%cog_right.rotation.x = -_current_yaw * COG_TURN_RATIO

# —— 俯仰 ——

# 俯仰对齐弹丸离弦瞬间的抛物线切线,使弹丸"顺膛而出"。
# 求解所需的起点几何与弹速由子类给出(backend 是单一事实来源),本类只把结果
# 落到 body.rotation.x,保证各模型的俯仰驱动方式一致。
#
# 不变式:body.rotation.x 与炮口仰角 1:1 线性且符号相反,故模型必须把炮管摆成
# body.rotation.x = 0 时正好水平(炮管沿 body 局部 -Y)。炮管在模型里若不水平,
# 整个俯仰就会偏掉一个固定角 —— 该偏置属于模型,请在 Blender 里改,不要在代码里补。
func set_target_position(in_position: Vector3):
	var center := Vector2(global_position.x, global_position.z)
	var aim := Vector2(_aim_dir.x, _aim_dir.z)
	if aim == Vector2.ZERO:
		return
	var pitch: float = _aim_pitch(center, aim, Vector2(in_position.x, in_position.z))
	%body.rotation.x = -pitch

# 求解出膛俯仰(弧度)。入参均为世界 XZ 平面坐标:in_center=炮塔中心,in_aim=单位朝向,
# in_target=目标位置。起点几何(转轴/起点偏移)与弹速由各模型的弹道决定。
@abstract
func _aim_pitch(in_center: Vector2, in_aim: Vector2, in_target: Vector2) -> float

# —— 状态机(backend state/progress → 子类动画钩子)——

# 武器内已装填一发(在弦/在膛)的阶段:那一发由武器自身的表现节点承担
# (弩的 %Arrow / 炮的装填炮弹),故这几个阶段备弹垛少显示一支,避免"垛 + 武器内一发"
# 比实际多出一支;发射(firing)起那一发已离膛,不再计入。
const HELD_STATES: Array[String] = ["loading", "charging", "ready"]

# 状态变化:记录阶段并派发到对应钩子。
# 子类若需额外语义(如同状态早退、或无论状态变化都要刷新表现),覆写并调用 super。
func set_state(in_state: String):
	_state = in_state
	_apply_ammo_delta()
	match in_state:
		"loading":
			_on_loading()
		"firing":
			_on_firing()
		_:
			_on_resting()

# 依据当前阶段更新备弹垛的显示差异量(见 HELD_STATES)。
func _apply_ammo_delta():
	if not _ammo_stack:
		return
	_ammo_stack.count_delta = -1 if _state in HELD_STATES else 0

# 蓄力进度变化:backend 保证 [0,1] 归一化(见 AGENTS.md §5.4 progress 契约)。
func set_progress(in_progress: float):
	_on_progress(in_progress)

# 上弦/装弹进度([0,1]):loading 阶段"从备弹垛取一发"的表现由它驱动(弩:端箭上弦;
# 炮:炮弹入膛)。与 set_progress(蓄力)分开 —— 两段进度由 backend Turret 分别给出,
# 故取弹时长以 backend 的 load_time() 为单一事实来源,前端不再自带一份时长常量。
# 子类在各自的 loading 处理里按本值采样,不累积状态(重绑/回放自洽)。
func set_load_progress(in_progress: float):
	_load_progress = clampf(in_progress, 0.0, 1.0)

# 进入装填(loading):把发射机构复位到"能再装一发"的姿态。
@abstract
func _on_loading()

# 进入开火(firing):起振本模型的开火动画。
@abstract
func _on_firing()

# 进入其余状态(idle/charging/ready):复位开火期间留下的临时形变。
@abstract
func _on_resting()

# 采样蓄力进度:把 [0,1] 映射成模型姿态。
@abstract
func _on_progress(in_progress: float)

# —— 备弹垛 ——

# %AmmoStack 挂在 cog_top 下,随炮塔水平转向;姿态/几何(item_type、target_length、
# 摆放锚点…)全部在各模型 .tscn 里配,编辑器里可直观调。
@onready var _ammo_stack: ItemStack = %AmmoStack

# 绑定后端展示仓(由 BuildingActor 转发):垛跟随 Bag 的 item_type/count 显示备弹。
# 子类若有额外表现(如弦上箭显隐)可覆写并调用 super。
func bind_bag(in_bag: Bag):
	if _ammo_stack:
		_ammo_stack.bind(in_bag)
