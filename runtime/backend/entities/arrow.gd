class_name Arrow
extends Entity

# —— 弹道物理(前后端共用同一套公式:弩身瞄准与箭矢视觉都读它,避免两份实现)——
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

var damage: Damage = Damage.physical(10)

var target_entity_ref: WeakRef = null
var target_position: Vector2 = Vector2.ZERO
var target_entity: Entity:
	get:
		if target_entity_ref:
			return target_entity_ref.get_ref()
		return null

# —— 弹道表现数据(由发射者 Crossbow 在 fire() 里注入;供 frontend 画抛物线视觉)——
# 这些是"从弦上射出"的表现参数:发射高度(弩口离地)、预计飞行时长(px 命中时刻),
# 以及内部计时,用于把竖直方向抬成抛物线。命中仍由 2D position==target_position 判定,
# 这里只额外暴露给 frontend 用于竖直位移,不改变命中逻辑。
var launch_height: float = 0.0    # 发射瞬间的世界高度(弩口离地)
var flight_time: float = 0.0      # 预计飞行时长(秒),由发射点→目标距离 / move_speed
var _initial_distance: float = 0.0  # 发射点→目标的初始水平距离(用于距离派生进度)

func set_target_entity(in_target_entity: Entity):
	target_entity_ref = weakref(in_target_entity)
	target_position = in_target_entity.position
	direction = (target_position - position).normalized()
	# 预计飞行时长 = 水平距离 / 速度(用于抛物线进度;目标移动时仍按此线性推进)。
	# 速度小于等于 0 时防除零。
	var horiz: float = position.distance_to(target_position)
	if move_speed > 0.0:
		flight_time = horiz / move_speed
	else:
		flight_time = 1.0
	_initial_distance = maxf(horiz, 0.0001)

# 飞行进度 [0,1]:按"剩余水平距离 / 初始距离"派生——目标静止/移动都保证命中瞬间
# 精确收敛到 1(Y=0),避免"箭未落地就被吞"的超前跳变。追踪弹每帧刷新 target_position,
# 故剩余距离持续缩短;追赶远离目标时也不会提前饱和(时间钟则会)。
func flight_progress() -> float:
	var remaining: float = position.distance_to(target_position)
	return 1.0 - clampf(remaining / _initial_distance, 0.0, 1.0)

func tick(in_delta: float):
	if target_entity:
		target_position = target_entity.position
	position = position.move_toward(target_position, move_speed * in_delta)
	if position.is_equal_approx(target_position):
		if target_entity:
			target_entity.take_damage(damage)
		Level.current.room.remove_entity(id)
