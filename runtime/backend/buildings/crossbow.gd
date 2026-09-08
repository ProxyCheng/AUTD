class_name Crossbow
extends Workshop

# 弩炮:工人驱动的蓄力/发射机器(生命周期见 Workshop 基类)。
# 一次生产 = 本班值岗期间射出一发弩箭。满弦但未开火时工人继续值守(负责转身瞄准);
# 射出后工人离岗,基类按 _needs_worker() 自动补员。
# 无人值守时整塔停摆(不寻敌、不转向、不开火);有待发/蓄力中需求时才需要操作手。

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
var _shift_fired: bool = false  # 本班值岗是否已射出一发(完成一次生产)

# 内容量可观察属性(供 frontend 显示旁侧备箭;复用 BuildingActor 鸭子转发管线)。
# 注意 stored_count 镜像 input_bag.count;前端展示时会再扣掉"在弦上的一支"。

# 容量(只读,供 frontend 归一化显示)
var capacity: int = 10:
	get:
		return capacity

# 存量镜像(input_bag.count 的对外可观察副本)。setter 只由内部 _sync_stored_count 驱动。
var stored_count: int = 0:
	get:
		return stored_count
	set(in_count):
		if in_count == stored_count:
			return
		stored_count = in_count
		stored_count_changed.emit()
signal stored_count_changed()

func _ready():
	input_bag = Bag.new()
	add_child(input_bag)
	input_bag.owner = owner
	input_bag.item_type = "arrow"
	input_bag.max_count = capacity
	# 纯请求方:低于上限即求补到满,永不外供(无富余可出)
	input_bag.preferred_min_count = input_bag.max_count
	input_bag.preferred_max_count = input_bag.max_count
	input_bag.access_position = Vector2(axis)
	input_bag.count_changed.connect(_sync_stored_count)
	_register_bag()
	_sync_stored_count()
	_maintain_manning()

# input_bag 计数变化 → 同步镜像属性,经 setter 触发 stored_count_changed
func _sync_stored_count():
	stored_count = input_bag.count if input_bag else 0

func is_work_done() -> bool:
	return _shift_fired

# 需要工人的条件:蓄力未完(还有活要干),或满弦但本轮尚未射出(需操作手值守待敌)。
# 发射后才暂时不需要,等松弦动画结束、fire_timer 归零再自动补位下一班。
func _needs_worker() -> bool:
	# 无弹药时无需顶岗(等 logistics 补货);否则按未射/蓄力中判断
	return _has_ammo() and (not _shift_fired or fire_timer < CHARGE_TIME)

func _has_ammo() -> bool:
	return input_bag and input_bag.count > 0

# 机器帧推进(基类 tick 已先做值守心跳与补员维护):弩炮为 workload 驱动,
# 蓄力经 worker 注入 work() 累积,这里负责瞄准、firing 松弦计时与发射判定。
func _tick_machine(in_delta: float):
	if state == "firing":
		fire_anim_timer -= in_delta
		progress = clampf(fire_anim_timer / FIRE_TIME, 0, 1)
		if fire_anim_timer <= 0:
			fire_timer = 0
			state = "idle"
			progress = 0
		return
	if not _is_manned():
		return
	target = find_target()
	_rotate_aim(in_delta)
	if fire_timer >= CHARGE_TIME:
		if target and is_aimed() and fire():
			# 满弦且对准且有人值守且有弹药→发射;firing 松弦动画由 tick 时钟驱动
			state = "firing"
			fire_anim_timer = FIRE_TIME
			progress = 1
			return
		# 满弦但尚未对准 / 暂无目标 / 弹药耗尽待补:保持待发姿态
		state = "ready"
		progress = 1
		return
	state = "charging"
	progress = fire_timer / CHARGE_TIME

# worker 每帧注入劳动量(delta * efficiency),累积为蓄力进度。
# 新一轮值岗(上一工人离岗后首次注入)经基类 _reset_shift() 清零发射标记。
func _apply_workload(in_workload: float):
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

func _reset_shift():
	_shift_fired = false

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

func fire() -> bool:
	if not target:
		return false
	# 消耗 1 支弩箭弹药;无弹则不开火(等 logistics 补货)
	if not _has_ammo():
		return false
	input_bag.remove_count(1)
	var room: Room = Level.current.room
	var arrow: Arrow = Entity.create("arrow")
	arrow.position = Vector2(axis.x, axis.y)
	arrow.move_speed = 10
	arrow.set_target_entity(target)
	room.add_entity(arrow)
	_shift_fired = true  # 本班值岗完成一次生产,工人下一 tick 离岗
	return true

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

# —— Logistics 注册/注销 input_bag(供补弹调度) ——

func _exit_tree():
	_unregister_bag()
	super._exit_tree()

func _register_bag():
	var logistics: Logistics = _get_logistics()
	if logistics:
		logistics.register_bag(input_bag)

func _unregister_bag():
	var logistics: Logistics = _get_logistics()
	if logistics:
		logistics.unregister_bag(input_bag.id)

func _get_logistics() -> Logistics:
	if not Level.current:
		return null
	return Level.current.logistics
