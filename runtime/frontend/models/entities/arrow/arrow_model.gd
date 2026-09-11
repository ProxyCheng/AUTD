class_name ArrowModel
extends Node3D

# 箭矢表现模型:水平位置由 backend 的 2D position 决定(EntityActor 写 actor.position),
# 本模型只负责"飞行弧线"——竖直抬升(抛物线)与 3D 朝向(俯仰随抛物线切线)。
# 模型朝向(箭尖指向)已在 arrow.tscn 内摆好,脚本不再改 mesh 姿态。
#
# 弹道公式本体在 backend(Arrow.arc_slope / Arrow.launch_pitch / Arrow.GRAVITY),
# 这里只做委托,保证前后端(弩身瞄准与箭矢视觉)用的是同一套实现。

func set_state(in_state: String):
	pass

static func _arc_slope(in_t: float, in_launch_height: float, in_flight_time: float) -> float:
	return Arrow.arc_slope(in_t, in_launch_height, in_flight_time)

# 离弦仰角(弧度):委托 backend,见 Arrow.launch_pitch。
static func launch_pitch(in_horizontal_distance: float, in_launch_height: float, in_move_speed: float) -> float:
	return Arrow.launch_pitch(in_horizontal_distance, in_launch_height, in_move_speed)

# 飞行表现:按进度 in_progress 抬升 Y 到抛物线,并让箭朝向抛物线切线方向
# (先上仰、后下俯),而非始终水平。由 EntityActor 在位置/朝向变化时转发 backend 弹道数据。
#   in_direction    水平飞行方向(单位向量,x 为世界 x、y 为世界 z)
#   in_launch_height 发射瞬间的世界高度(起点离地)
#   in_flight_time   预计飞行时长(秒),与 in_move_speed 一起把竖直斜率换算成俯仰
#   in_move_speed    水平速度(世界单位/秒)
func set_flight(in_progress: float, in_direction: Vector2, in_launch_height: float, in_flight_time: float, in_move_speed: float):
	var t: float = clampf(in_progress, 0.0, 1.0)
	# 抛物线:起点=发射高度,终点=0(目标地面),拱高由重力与飞行时长决定(A = ½·G·T²)。
	var arc: float = 0.5 * Arrow.GRAVITY * in_flight_time * in_flight_time
	position.y = lerpf(in_launch_height, 0.0, t) + arc * t * (1.0 - t)
	_aim_along_tangent(t, in_direction, in_launch_height, in_flight_time, in_move_speed)

# 朝向抛物线切线:dy/dt(对进度 t)= -h + A·(1-2t);
# 竖直速率 / 水平速率 = (dy/dt / flight_time) / move_speed —— 用它构造俯仰。
# look_at 让节点 -Z 指向切线方向(箭尖已摆成 -Z),并保留本模型缩放。
func _aim_along_tangent(in_t: float, in_direction: Vector2, in_launch_height: float, in_flight_time: float, in_move_speed: float):
	if in_direction == Vector2.ZERO:
		return
	var dy_dt: float = _arc_slope(in_t, in_launch_height, in_flight_time)
	var vy_rate: float = 0.0
	if in_move_speed > 0.0 and in_flight_time > 0.0:
		vy_rate = (dy_dt / in_flight_time) / in_move_speed
	var aim: Vector3 = Vector3(in_direction.x, vy_rate, in_direction.y).normalized()
	look_at(global_position + aim, Vector3.UP)
