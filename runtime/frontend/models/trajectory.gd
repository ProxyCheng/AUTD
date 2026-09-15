class_name Trajectory

# 弹道/瞄准求解(纯表现):投射物在 frontend 用抛物线渲染,发射器炮管也按离弦切线俯仰,
# 两者共用这里的公式。backend 的投射物只做平面运动,不感知重力/抛物线(见 backend Ballistic),
# 故 GRAVITY 与整套弹道公式都属于表现层,放这里。
#
# —— 弹道物理 ——
# 重力加速度(世界单位/秒²)。水平速度恒定 v_h,飞行时长 T = 水平距离/v_h,拱高系数 A = ½·G·T²。
static var GRAVITY: float = 9.8

# 抛物线在进度 t 处的竖直斜率 dy/dt(未除以水平速率):-h + A·(1-2t)。
static func arc_slope(in_t: float, in_launch_height: float, in_flight_time: float) -> float:
	var arc: float = 0.5 * GRAVITY * in_flight_time * in_flight_time
	return -in_launch_height + arc * (1.0 - 2.0 * in_t)

# 离弦仰角(弧度):抛物线在 t=0 处切线俯仰角 = atan2(竖直速率/水平速率, 1)。
# 竖直速率/水平速率 = (dy/dt0 / T) / v_h = dy/dt0 / 水平距离。
static func launch_pitch(in_horizontal_distance: float, in_launch_height: float, in_move_speed: float) -> float:
	if in_horizontal_distance <= 0.0 or in_move_speed <= 0.0:
		return 0.0
	var flight_time: float = in_horizontal_distance / in_move_speed
	return atan2(arc_slope(0.0, in_launch_height, flight_time) / in_horizontal_distance, 1.0)

# —— 发射器几何求解(转轴 P + 起点偏移 S,发射器局部系)——
# 各发射器(弩炮/火炮)只持有自己的静态几何(见 Crossbow/Cannon 的 PIVOT_*/SPAWN_*),
# 求解逻辑集中在此:避免每加一种发射器就复制一遍同样的向量旋转与不动点迭代。
# S = P + R(θ)·S_off —— 起点随离弦仰角 θ 绕转轴旋转。
static func spawn_offset_at(in_pitch: float, in_pivot: Vector2, in_spawn: Vector2) -> Vector2:
	var c: float = cos(in_pitch)
	var s: float = sin(in_pitch)
	return Vector2(
		in_pivot.x + in_spawn.x * c - in_spawn.y * s,
		in_pivot.y + in_spawn.x * s + in_spawn.y * c
	)

# 求命中目标所需的离弦仰角:发射点随 θ 抬升,θ 与发射高度互相依赖,做几次不动点迭代收敛。
static func aim_pitch_for(in_center: Vector2, in_aim_dir: Vector2, in_target_pos: Vector2,
		in_pivot: Vector2, in_spawn: Vector2, in_speed: float) -> float:
	var pitch: float = 0.0
	for _i in range(4):
		var off: Vector2 = spawn_offset_at(pitch, in_pivot, in_spawn)
		var spawn_pos: Vector2 = in_center + in_aim_dir * off.x
		pitch = launch_pitch(spawn_pos.distance_to(in_target_pos), off.y, in_speed)
	return pitch

# 离弦瞬间的发射点高度:供投射物模型把抛物线起点抬到炮口。
# in_horizontal_distance = 发射点→目标的初始水平距离(与 backend Ballistic.flight_distance 同义)。
static func launch_height_for(in_horizontal_distance: float, in_speed: float,
		in_pivot: Vector2, in_spawn: Vector2) -> float:
	var pitch: float = 0.0
	for _i in range(4):
		var off: Vector2 = spawn_offset_at(pitch, in_pivot, in_spawn)
		pitch = launch_pitch(in_horizontal_distance, off.y, in_speed)
	return spawn_offset_at(pitch, in_pivot, in_spawn).y
