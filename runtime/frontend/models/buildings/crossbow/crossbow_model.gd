class_name CrossbowModel
extends Node3D

const ANIM_NAME: StringName = &"bone|boneAction_001"

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

func set_state(in_state: String):
	# 状态只描述 backend 所处阶段(idle/charging/ready/firing);
	# 姿态一律由 set_progress 驱动,此处无需分支。
	pass

func _apply_pose(in_time: float):
	# seek 需要激活态才刷新关键帧姿态:暂停中先 play 再 seek 再暂停
	if not %AnimationPlayer.is_playing():
		%AnimationPlayer.play(ANIM_NAME)
	%AnimationPlayer.seek(in_time, true)
	%AnimationPlayer.pause()

func set_progress(in_progress: float):
	# 归一化 progress → 动画时间:0=松弛(末尾)、1=满弦(起点)。
	# 蓄力(0→1)反向回弦,射击(firing 1→0)正向播完一发。
	# 若美术动画起止语义相反,把 seek 改为 in_progress * length 即可。
	var length: float = %AnimationPlayer.current_animation_length
	_apply_pose((1 - in_progress) * length)

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
