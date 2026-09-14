class_name Cannon
extends Crossbow

# 火炮:与弩炮同构的"工人驱动蓄力/发射"机器 —— 整条值守/装填/蓄力/瞄准/发射状态机
# 直接复用 Crossbow,只覆写它的调参钩子,不复制任何状态机代码。与弩炮的区别:
#   * 弹药为 cannonball(车间以石头合成),弹丸为 Cannonball 实体;
#   * 弹丸更慢、装填/蓄力更久、备弹更少,但射程更远,命中造成圆形区域伤害(见 Cannonball)。
# 发射几何沿用 Crossbow 的静态值(两模型同为炮塔式底座,尺度相近);若日后需单独标定,
# 覆写 pivot()/spawn() 即可,无需改基类。

# —— 与弩炮不同的调参(覆写 Crossbow 钩子)——
const CANNON_CHARGE_TIME: float = 5.0
const CANNON_FIRE_TIME: float = 0.2
const CANNON_LOAD_TIME: float = 1.2
const CANNON_AMMO_CAPACITY: int = 6
# 攻击范围(半边长,格子单位):火炮射程大于弩炮(3.0)。
const CANNON_ATTACK_RANGE: float = 4.0
# 炮弹水平飞行速度(世界单位/秒)。static:前端模型 CannonModel 读它算炮身俯仰,
# 与后端 fire() 共用同一值(与 Crossbow 的 PIVOT_*/SPAWN_* 同属"前后端共用弹道参数"约定)。
static var PROJECTILE_SPEED: float = 9.0

func ammo_type() -> String:
	return "cannonball"

func ammo_capacity() -> int:
	return CANNON_AMMO_CAPACITY

func projectile_type() -> String:
	return "cannonball"

func projectile_speed() -> float:
	return PROJECTILE_SPEED

func charge_time() -> float:
	return CANNON_CHARGE_TIME

func fire_time() -> float:
	return CANNON_FIRE_TIME

func load_time() -> float:
	return CANNON_LOAD_TIME

func get_attack_range() -> float:
	return CANNON_ATTACK_RANGE
