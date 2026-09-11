class_name Arrow
extends Entity

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
