class_name Ballistic
extends Entity

# 弹道投射物基类:箭矢/炮弹共用"发射参数 → 平面飞行 → 命中"契约。
# backend 只做平面运动(水平追踪目标点),重力/抛物线纯属表现,由 frontend 的 Trajectory
# 模拟(见 runtime/frontend/models/trajectory.gd),backend 不感知。
# 子类只决定命中效果(Arrow 单体伤害 / Cannonball 区域伤害)。

var damage: Damage = Damage.physical(10)

var target_entity_ref: WeakRef = null
var target_position: Vector2 = Vector2.ZERO
var target_entity: Entity:
	get:
		if target_entity_ref:
			return target_entity_ref.get_ref()
		return null

# 发射点→目标的初始水平距离(用于距离派生进度;frontend 据此换算飞行时长与拱高)。
var flight_distance: float = 0.0

func set_target_entity(in_target_entity: Entity):
	target_entity_ref = weakref(in_target_entity)
	target_position = in_target_entity.position
	direction = (target_position - position).normalized()
	flight_distance = maxf(position.distance_to(target_position), 0.0001)

# 飞行进度 [0,1]:按"剩余水平距离 / 初始距离"派生——目标静止/移动都保证命中瞬间
# 精确收敛到 1,避免"投射物未落地就被吞"的超前跳变。追踪弹每帧刷新 target_position,
# 故剩余距离持续缩短;追赶远离目标时也不会提前饱和(时间钟则会)。
func flight_progress() -> float:
	var remaining: float = position.distance_to(target_position)
	return 1.0 - clampf(remaining / flight_distance, 0.0, 1.0)

func tick(in_delta: float):
	if target_entity:
		target_position = target_entity.position
	position = position.move_toward(target_position, move_speed * in_delta)
	if position.is_equal_approx(target_position):
		_on_hit()

# 命中效果:基类默认对主目标造成单体伤害后自毁;子类可覆写为区域伤害等(见 Cannonball)。
func _on_hit():
	if target_entity:
		target_entity.take_damage(damage)
	Level.current.room.remove_entity(id)
