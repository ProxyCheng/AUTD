class_name Crossbow
extends Workshop

const CHARGE_TIME: float = 3.0
const FIRE_TIME: float = 0.1
# 炮塔转向角速度(弧度/秒),目标变化时以该速度平滑旋转,不瞬移
const ROTATE_SPEED: float = 2.5
# 判定"对准"的朝向夹角容差(弧度)
const AIM_EPSILON: float = 0.05
# 有人值守的判定窗口:超过该时长无 worker 注入 work() 即视为无人,塔停摆
const MANNED_TIMEOUT: float = 0.2
# 岗位点:机器所在格子的一个固定角(相对机器坐标的偏移),可按模型微调方向/大小
const WORK_ENTRY_OFFSET: Vector2 = Vector2(0.4, 0.4)

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
var manning_task: ManBuildingTask = null
var _worker_requested: bool = false
var _manned_timer: float = 0  # >0 表示有人值守(近期有 worker 注入 work())
var _shift_fired: bool = false  # 本班值岗是否已射出一发(完成一次生产)

func _ready():
	input_bag = Bag.new()
	add_child(input_bag)
	input_bag.owner = owner
	input_bag.item_type = "arrow"
	input_bag.disired_min_count = input_bag.disired_max_count
	_maintain_manning()

func _exit_tree():
	_cancel_worker_request()

# 一次生产 = 本班值岗期间射出一发弩箭。满弦但未开火时工人继续值守(负责转身瞄准);
# 射出后工人离岗,塔再请求补员。无人值守时塔不寻敌、不转向、不开火。
func is_work_done() -> bool:
	return _shift_fired

func _get_manager() -> LaborManager:
	if not Level.current:
		return null
	return Level.current.labor_manager

# 每帧按需维护:无人且未满弦、没有在途请求时,向 LaborManager 注册一个顶岗任务。
# 任务在射出一发后完成(或工人流失被取消),节点释放后自动补位;
# LaborManager 会派最近的空闲劳工(通常仍是刚离岗、守在岗位旁的那位)。
func _maintain_manning():
	if not is_inside_tree():
		return
	var manager := _get_manager()
	if not manager:
		return
	if _worker_requested:
		if manning_task and is_instance_valid(manning_task):
			return
		_worker_requested = false
	if fire_timer < CHARGE_TIME and not _is_manned():
		_worker_requested = true
		manning_task = ManBuildingTask.new(self, _work_entry_position())
		manager.register_task(manning_task)

func _cancel_worker_request():
	_worker_requested = false
	var manager := _get_manager()
	if is_instance_valid(manager) and manning_task and is_instance_valid(manning_task):
		manager.cancel_task(manning_task)
	manning_task = null

# 岗位点:机器所在格子固定一个角(相对自身坐标 WORK_ENTRY_OFFSET),贴机器且不重叠。
func _work_entry_position() -> Vector2:
	return Vector2(axis) + WORK_ENTRY_OFFSET

func _is_manned() -> bool:
	return _manned_timer > 0

func tick(in_delta: float):
	# 本塔为 workload 驱动:蓄力经 worker 注入 work(),tick 负责瞄准与 firing 计时,
	# 以及"满弦 + 对准 + 有人值守"的发射判定。无人值守时整塔停摆(不寻敌/不转/不射)。
	if state == "firing":
		fire_anim_timer -= in_delta
		progress = clampf(fire_anim_timer / FIRE_TIME, 0, 1)
		if fire_anim_timer <= 0:
			fire_timer = 0
			state = "idle"
			progress = 0
		return
	_manned_timer = maxf(_manned_timer - in_delta, 0)
	_maintain_manning()
	if not _is_manned():
		return
	target = find_target()
	_rotate_aim(in_delta)
	if fire_timer >= CHARGE_TIME:
		if target and is_aimed():
			# 满弦且对准且有人值守→发射;firing 松弦动画由 tick 时钟驱动
			fire()
			state = "firing"
			fire_anim_timer = FIRE_TIME
			progress = 1
			return
		# 满弦但尚未对准(或暂无目标):保持待发姿态,对准即射
		state = "ready"
		progress = 1

# worker 每帧注入劳动量(delta * efficiency),累积为蓄力进度。
# 每次注入都刷新"有人值守"窗口;新一轮值岗(上一工人离岗后首次注入)清零发射标记。
func work(in_workload: float):
	var was_unmanned := not _is_manned()
	_manned_timer = MANNED_TIMEOUT
	if was_unmanned:
		_shift_fired = false
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
	_shift_fired = true  # 本班值岗完成一次生产,工人下一 tick 离岗

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
