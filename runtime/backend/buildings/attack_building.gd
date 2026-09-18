@abstract
class_name AttackBuilding
extends Workshop

# 攻击型建筑基类 = 攻击倾向(可观察配置) + 目标选取(按倾向) + 瞄准状态(目标/朝向);
# 具体弹种/弹速/时序/发射几何由子类钩子给出(见 Turret 及其子类 Crossbow/Cannon),本类不推进时序、不产出弹丸。
#
# 攻击倾向:target_preference 决定攻击目标的选取偏好,取值见 TARGET_PREF* 常量
# (nearest 最近 / front 最前 / last 末尾 / strongest 最强),经 set_target_preference() 切换并广播。
# front/last 的"前后"以主基地为锚(见 _base_distance_sq),不写死任何坐标轴 —— 行进方向随关卡而变。
#
# 瞄准:target/aim_direction 均为可观察属性(§5.4),由子类状态机在自己的 tick 中经
# find_target()/_rotate_aim()/is_aimed() 驱动;本类不自行推进,也不感知武器形态。

# —— 攻击倾向(可观察配置)——
# 取值常量:String(全小写 snake,符合仓库"类型标识字符串"惯例)
const TARGET_PREF_NEAREST: String = "nearest"
const TARGET_PREF_FRONT: String = "front"
const TARGET_PREF_LAST: String = "last"
const TARGET_PREF_STRONGEST: String = "strongest"
# 默认:最前(越靠前即越接近主基地推进方向,y 越负越前)
const TARGET_PREF_DEFAULT: String = TARGET_PREF_FRONT

var target_preference: String = TARGET_PREF_DEFAULT:
	get:
		return target_preference
	set(in_preference):
		if in_preference == target_preference:
			return
		target_preference = in_preference
		target_preference_changed.emit()
signal target_preference_changed()

func set_target_preference(in_preference: String):
	if in_preference not in [TARGET_PREF_NEAREST, TARGET_PREF_FRONT, TARGET_PREF_LAST, TARGET_PREF_STRONGEST]:
		return
	target_preference = in_preference

# 攻击范围(半边长,格子单位):寻敌区域为以本建筑所在格为中心、边长 2×ATTACK_RANGE 的正方形。
const ATTACK_RANGE: float = 3.0

# 攻击范围半边长(格子单位),见 ATTACK_RANGE;供前端绘制范围面。
func get_attack_range() -> float:
	return ATTACK_RANGE

# —— 攻击目标选取:按 target_preference 排序 ——

# 范围内(以 axis 为圆心、半径 get_attack_range() 的圆形)所有存活敌方,按 target_preference 排序后取第一个。
#   nearest:距离平方最小(离本建筑最近)
#   front:到主基地的距离平方最小(最靠前 = 最深入我方、最紧迫)
#   last:到主基地的距离平方最大(末尾 = 最后入场、离主基地最远)
#   strongest:health 最高
func find_target() -> Entity:
	var room: Room = Level.current.room
	var range_half: float = get_attack_range()
	# Room 只提供矩形查询:先用外接正方形粗筛,再按圆形半径精筛(剔除四角)。
	var entities: Array = room.get_entities_in_rect(Rect2(axis.x - range_half, axis.y - range_half, range_half * 2.0, range_half * 2.0))
	var max_distance_sq: float = range_half * range_half
	var candidates: Array[Entity] = []
	for entity: Entity in entities:
		if entity is not Enemy:
			continue
		if not entity.is_alive():
			continue
		if _distance_sq(entity.position) > max_distance_sq:
			continue
		candidates.append(entity)
	if candidates.is_empty():
		return null
	match target_preference:
		TARGET_PREF_FRONT:
			candidates.sort_custom(func(a: Entity, b: Entity) -> bool:
				return _base_distance_sq(a.position) < _base_distance_sq(b.position))
		TARGET_PREF_LAST:
			candidates.sort_custom(func(a: Entity, b: Entity) -> bool:
				return _base_distance_sq(a.position) > _base_distance_sq(b.position))
		TARGET_PREF_STRONGEST:
			candidates.sort_custom(func(a: Entity, b: Entity) -> bool:
				return a.health > b.health)
		_:  # nearest(默认)
			candidates.sort_custom(func(a: Entity, b: Entity) -> bool:
				return _distance_sq(a.position) < _distance_sq(b.position))
	return candidates[0]

# 到本建筑的距离平方(避免开方)。
func _distance_sq(in_position: Vector2) -> float:
	var delta: Vector2 = in_position - Vector2(axis)
	return delta.length_squared()

# 到主基地的距离平方(避免开方):front/last 的"前后"锚点。
# 锚在主基地而不是某个坐标轴,是因为行进方向随关卡而变:level0 的敌人生成器与主基地同在
# y=4 一行、敌人沿 +x 推进,若按 position.y 排序会退化成"所有敌人 y 相同"的常数比较,
# 于是 front/last 取到同一个敌人(见 test/attack_preference_test.gd)。
# 主基地缺失时(无基地的测试场景)退化为到本建筑的距离,排序等价于 nearest。
func _base_distance_sq(in_position: Vector2) -> float:
	var anchor: Vector2 = Vector2(MainBase.current.axis) if MainBase.current else Vector2(axis)
	var delta: Vector2 = in_position - anchor
	return delta.length_squared()

# —— 瞄准状态 ——

# 炮塔转向角速度(弧度/秒),目标变化时以该速度平滑旋转,不瞬移
const ROTATE_SPEED: float = 2.5
# 判定"对准"的朝向夹角容差(弧度)
const AIM_EPSILON: float = 0.05

var target: Entity:
	get:
		return target
	set(in_target):
		if in_target == target:
			return
		target = in_target
		target_changed.emit()
signal target_changed()
# 当前炮口朝向(单位向量,世界 XZ 平面;y 分量为世界 z),由 tick 限速逼近目标方位
var aim_direction: Vector2 = Vector2(0, 1):
	get:
		return aim_direction
	set(in_aim_direction):
		if in_aim_direction.is_equal_approx(aim_direction):
			return
		aim_direction = in_aim_direction
		aim_direction_changed.emit()
signal aim_direction_changed()

# 以 ROTATE_SPEED 限速把 aim_direction 转向目标方位;无目标时保持当前朝向。
# 跳变幅度小于单帧步进时直接吸附到目标,避免抖动。
func _rotate_aim(in_delta: float):
	if not target:
		return
	var to_target: Vector2 = _target_direction()
	var diff: float = aim_direction.angle_to(to_target)
	var step: float = ROTATE_SPEED * in_delta
	if absf(diff) > step:
		aim_direction = aim_direction.rotated(signf(diff) * step)
	else:
		aim_direction = to_target

func _target_direction() -> Vector2:
	return Vector2(target.position.x - axis.x, target.position.y - axis.y).normalized()

func is_aimed() -> bool:
	if not target:
		return false
	return absf(aim_direction.angle_to(_target_direction())) <= AIM_EPSILON
