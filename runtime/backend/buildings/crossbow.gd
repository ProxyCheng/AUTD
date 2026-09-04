extends Building

const CHARGE_TIME: float = 3.0
const FIRE_TIME: float = 0.1

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

var input_bag: Bag

func _ready():
	input_bag = Bag.new()
	add_child(input_bag)
	input_bag.owner = owner
	input_bag.item_type = "arrow"
	input_bag.disired_min_count = input_bag.disired_max_count

func tick(in_delta: float):
	# progress 全程连续:charging 0→1(拉弦)、firing 1→0(释放=正向播完动画)、
	# idle/ready 停驻。模型只按归一化 progress 采样动画姿态,不依赖播放器时钟。
	if state == "firing":
		fire_anim_timer -= in_delta
		progress = clampf(fire_anim_timer / FIRE_TIME, 0, 1)
		if fire_anim_timer <= 0:
			fire_timer = 0
			state = "idle"
			progress = 0
		return
	target = find_target()
	if state == "idle":
		# 只要不在射击窗口就持续蓄力(与是否有目标无关)
		state = "charging"
		progress = 0
	fire_timer = minf(fire_timer + in_delta, CHARGE_TIME)
	if fire_timer >= CHARGE_TIME:
		if target:
			fire()
			state = "firing"
			fire_anim_timer = FIRE_TIME
			progress = 1
			return
		# 满弦但无目标:保持待发姿态,目标出现即射
		state = "ready"
		progress = 1
		return
	state = "charging"
	progress = fire_timer / CHARGE_TIME

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
