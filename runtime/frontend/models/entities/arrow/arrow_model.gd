class_name ArrowModel
extends Node3D

# 箭矢表现模型:水平位置由 backend 的 2D position 决定(EntityActor 写 actor.position),
# 本模型只负责"飞行弧线"——竖直抬升(抛物线)与 3D 朝向(俯仰随抛物线切线)。
# 模型朝向(箭尖指向)已在 arrow.tscn 内摆好,脚本不再改 mesh 姿态。
#
# 抛物线/重力纯属表现,公式在 Trajectory(见 runtime/frontend/models/trajectory.gd);
# backend 只给平面轨迹(进度 + 初始水平距离),起点高度与飞行时长在这里按发射器几何补出。

# 发射器几何(与 Crossbow 的射箭几何同源:转轴 P + 起点偏移 S)。
func _pivot() -> Vector2:
	return Vector2(Crossbow.PIVOT_FORWARD, Crossbow.PIVOT_HEIGHT)

func _spawn() -> Vector2:
	return Vector2(Crossbow.SPAWN_FORWARD, Crossbow.SPAWN_HEIGHT)

func set_state(in_state: String):
	pass

# 飞行表现:按进度 in_progress 抬升 Y 到抛物线,并让箭朝向抛物线切线方向
# (先上仰、后下俯),而非始终水平。由 EntityActor 在位置/朝向变化时转发 backend 平面轨迹数据。
#   in_direction       水平飞行方向(单位向量,x 为世界 x、y 为世界 z)
#   in_move_speed      水平速度(世界单位/秒)
#   in_flight_distance 发射点→目标的初始水平距离(backend 单一事实来源)
func set_flight(in_progress: float, in_direction: Vector2, in_move_speed: float, in_flight_distance: float):
	var t: float = clampf(in_progress, 0.0, 1.0)
	var flight_time: float = in_flight_distance / in_move_speed if in_move_speed > 0.0 else 1.0
	var launch_height: float = Trajectory.launch_height_for(in_flight_distance, in_move_speed, _pivot(), _spawn())
	# 抛物线:起点=发射高度,终点=0(目标地面),拱高由重力与飞行时长决定(A = ½·G·T²)。
	var arc: float = 0.5 * Trajectory.GRAVITY * flight_time * flight_time
	position.y = lerpf(launch_height, 0.0, t) + arc * t * (1.0 - t)
	_aim_along_tangent(t, in_direction, launch_height, flight_time, in_move_speed)

# 朝向抛物线切线:dy/dt(对进度 t)= -h + A·(1-2t);
# 竖直速率 / 水平速率 = (dy/dt / flight_time) / move_speed —— 用它构造俯仰。
# look_at 让节点 -Z 指向切线方向(箭尖已摆成 -Z),并保留本模型缩放。
func _aim_along_tangent(in_t: float, in_direction: Vector2, in_launch_height: float, in_flight_time: float, in_move_speed: float):
	if in_direction == Vector2.ZERO:
		return
	var dy_dt: float = Trajectory.arc_slope(in_t, in_launch_height, in_flight_time)
	var vy_rate: float = 0.0
	if in_move_speed > 0.0 and in_flight_time > 0.0:
		vy_rate = (dy_dt / in_flight_time) / in_move_speed
	var aim: Vector3 = Vector3(in_direction.x, vy_rate, in_direction.y).normalized()
	look_at(global_position + aim, Vector3.UP)
