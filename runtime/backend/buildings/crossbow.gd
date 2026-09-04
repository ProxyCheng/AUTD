class_name Crossbow
extends Workshop

const CHARGE_TIME: float = 3.0
const FIRE_TIME: float = 0.1
# 炮塔转向角速度(弧度/秒),目标变化时以该速度平滑旋转,不瞬移
const ROTATE_SPEED: float = 2.5
# 判定"对准"的朝向夹角容差(弧度)
const AIM_EPSILON: float = 0.05

var fire_timer: float = 0
var fire_anim_timer: float = 0
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

var input_bag: Bag

func _ready():
	input_bag = Bag.new()
	add_child(input_bag)
	input_bag.owner = owner
	input_bag.item_type = "arrow"
	input_bag.disired_min_count = input_bag.disired_max_count

func tick(in_delta: float):
	# 本塔为 workload 驱动:蓄力(充能)完全经 work() 注入,此处不消耗时间。
	# tick 仅负责瞄准与 firing 动画计时,以及"满弦 + 对准"的发射判定。
	# 无 worker 注入 work() 时,fire_timer 恒为 0,塔停摆不开火。
	if state == "firing":
		fire_anim_timer -= in_delta
		progress = clampf(fire_anim_timer / FIRE_TIME, 0, 1)
		if fire_anim_timer <= 0:
			fire_timer = 0
			state = "idle"
			progress = 0
		return
	target = find_target()
	_rotate_aim(in_delta)
	if fire_timer >= CHARGE_TIME:
		if target and is_aimed():
			# 满弦且对准→发射;firing 松弦动画由 tick 时钟驱动
			fire()
			state = "firing"
			fire_anim_timer = FIRE_TIME
			progress = 1
			return
		# 满弦但尚未对准(或暂无目标):保持待发姿态,对准即射
		state = "ready"
		progress = 1

# worker 每帧注入劳动量(delta * efficiency),累积为蓄力进度。
# 充能命中 CHARGE_TIME 后停驻 ready,等待 tick 判定对准发射。
func work(in_workload: float):
	if state == "firing":
		# 射击窗口不接受劳作
		return
	if state == "idle":
		state = "charging"
		progress = 0
	fire_timer = minf(fire_timer + in_workload, CHARGE_TIME)
	if fire_timer >= CHARGE_TIME:
		state = "ready"
		progress = 1
		return
	state = "charging"
	progress = fire_timer / CHARGE_TIME

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

func fire():
	var room: Room = Level.current.room
	if not target:
		return
	var arrow: Arrow = Entity.create("arrow")
	arrow.position = Vector2(axis.x, axis.y)
	arrow.move_speed = 10
	arrow.set_target_entity(target)
	room.add_entity(arrow)

func find_target() -> Entity:
	var room: Room = Level.current.room
	var entities: Array = room.get_entities_in_rect(Rect2(axis.x - 3, axis.y - 3, 6, 6))
	for entity: Entity in entities:
		if entity is not Enemy:
			continue
		if not entity.is_alive():
			continue
		return entity
	return null
