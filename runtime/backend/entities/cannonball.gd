class_name Cannonball
extends Ballistic

# 炮弹:与弩箭共用同一套弹道(继承 Ballistic 的飞行/抛物线契约,前端 ArrowModel 的
# set_flight 表现直接复用),唯一区别是命中时对落点圆形范围内的所有敌人造成全额伤害
# (区域伤害),而非只打主目标。由 Cannon.fire() 经 Entity.create("cannonball") 实例化。

# 区域伤害半径(格子单位):以命中点(炮弹落点)为圆心的圆形范围。
const AREA_RADIUS: float = 1.5
# 单次命中对范围内每个敌人造成的伤害(全额,不随距离衰减)。
const DAMAGE_AMOUNT: float = 30.0

func _ready():
	# Ballistic 的 damage 默认是弩箭的单体伤害,这里换成炮弹的区域伤害值。
	damage = Damage.physical(DAMAGE_AMOUNT)
	super._ready()

# 命中:对落点圆形范围内所有存活敌人各造成一次全额伤害(含主目标),随后自毁。
# Room 只提供矩形查询:先用外接正方形粗筛,再按圆形半径精筛(剔除四角),与 Crossbow.find_target 同法。
func _on_hit():
	var room: Room = Level.current.room
	var range_half: float = AREA_RADIUS
	var candidates: Array = room.get_entities_in_rect(Rect2(
		target_position.x - range_half, target_position.y - range_half,
		range_half * 2.0, range_half * 2.0))
	var max_distance_sq: float = range_half * range_half
	for entity: Entity in candidates:
		if entity is not Enemy:
			continue
		if not entity.is_alive():
			continue
		if entity.position.distance_squared_to(target_position) > max_distance_sq:
			continue
		entity.take_damage(damage)
	room.remove_entity(id)
