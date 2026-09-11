class_name Crossbow
extends Workshop

# 弩炮:工人驱动的蓄力/发射机器(生命周期与仓管理见 Workshop 基类)。
# 一次生产 = 本班值岗期间射出一发弩箭。满弦但未开火时工人继续值守(负责转身瞄准);
# 射出后工人离岗,基类按 _needs_worker() 自动补员。
# 无人值守时整塔停摆(不寻敌、不转向、不开火);有待发/蓄力中需求时才需要操作手。
#
# 区别于产出建筑:弩炮只有一只弹药输入仓(arrow,纯需求方),没有输出仓——产出的是一次
# 发射这一即时效果,而非可存放的物品。该"攻击"按瞬时效果机械形态声明为一张配方:
#   inputs = [arrow × 1], output = "", workload_per_unit = CHARGE_TIME(蓄满一发的蓄力)
# 配方用于 GUI 展示(消耗箭、耗时、进度)与 active_recipe 高亮;弹药仓仍作为展示镜像
# (前端据 stored_count/capacity 显示旁侧备箭)。蓄力/瞄准/开火时序由本类自有状态机驱动。
#
# 攻击倾向:target_preference 决定攻击目标的选取偏好,取值见 TARGET_PREF* 常量
# (nearest 最近 / front 最前 / strongest 最强),经 set_target_preference() 切换并广播。

const CHARGE_TIME: float = 3.0
const FIRE_TIME: float = 0.1
# 装填耗时:工人到位后先把一支弩矢从备箭垛端上弦(前端播上弦动画),随后才开始拉弦。
# 这段时间弦保持松弛(progress=0),属于"端箭准备",不占用蓄力工作量。
const LOAD_TIME: float = 0.6
# 炮塔转向角速度(弧度/秒),目标变化时以该速度平滑旋转,不瞬移
const ROTATE_SPEED: float = 2.5
# 判定"对准"的朝向夹角容差(弧度)
const AIM_EPSILON: float = 0.05
# 弹药仓容量(纯需求方:低于上限即求补到满)
const AMMO_CAPACITY: int = 10
# 弩口相对弩中心的水平前移偏移(沿瞄准方向;世界单位)。发射时箭从弩口一侧飞出,
# 而非从格子中心弹出,便于前端"从弦上连贯射出"的视觉衔接。
const MUZZLE_FORWARD_OFFSET: float = 0.35
# 发射时的世界高度(弩口离地,约等于模型甲板+弩身中线;前端据此把箭抬高再画抛物线)。
const LAUNCH_HEIGHT: float = 0.78

# —— 配方声明:攻击 = 一次即时效果(无输出仓,消耗箭矢触发开火) ——
# 蓄满一发的蓄力由 base._apply_workload 累积 progress;满弦后由 _tick_machine 负责瞄准/发射。

func _ready():
	recipes = [_make_fire_recipe()]
	super._ready()

func _make_fire_recipe() -> RecipeData:
	var recipe := RecipeData.new()
	recipe.label = "Fire"
	recipe.output = ""
	recipe.workload_per_unit = CHARGE_TIME
	var arrow_input := RecipeInputData.new()
	arrow_input.item_type = "arrow"
	arrow_input.count = 1
	recipe.inputs = [arrow_input]
	return recipe

# —— 攻击倾向(可观察配置)——
# 取值常量:String(全小写 snake,符合仓库"类型标识字符串"惯例)
const TARGET_PREF_NEAREST: String = "nearest"
const TARGET_PREF_FRONT: String = "front"
const TARGET_PREF_STRONGEST: String = "strongest"
# 默认:最近
const TARGET_PREF_DEFAULT: String = TARGET_PREF_NEAREST

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
	if in_preference not in [TARGET_PREF_NEAREST, TARGET_PREF_FRONT, TARGET_PREF_STRONGEST]:
		return
	target_preference = in_preference

var fire_timer: float = 0
var fire_anim_timer: float = 0
# 装填计时:工人到位进入 loading 后倒计时;归零转为 charging(开始拉弦),再累计蓄力。
var load_timer: float = 0
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

# 弹药输入仓(arrow,纯需求方)。基类 _ready → _setup_bags 创建并注册;作展示镜像
# (stored_count 镜像 input_bag.count)。前端展示时会再扣掉"在弦上的一支"。
var input_bag: Bag
var _shift_fired: bool = false  # 本班值岗是否已射出一发(完成一次生产)

# 无输出仓配方:只建弹药输入仓并指定其为展示镜像(不调用 super,基类默认会按
# _produces() 建输出仓,而弩炮无配方产出)。
func _setup_bags():
	input_bag = _make_bag("AmmoBag", "arrow", AMMO_CAPACITY, true, 1)
	_bind_mirror(input_bag)

# 攻击建筑:驱动它的顶岗任务优先级=11(生产 10 再 +1),保证弩炮始终优先有人值守
func manning_priority() -> int:
	return 11

func is_work_done() -> bool:
	return _shift_fired

# 需要工人的条件:蓄力未完(还有活要干),或满弦但本轮尚未射出(需操作手值守待敌)。
# 发射后才暂时不需要,等松弦动画结束、fire_timer 归零再自动补位下一班。
# 顺带 _selected_recipe() 同步 active_recipe(GUI 高亮当前 Fire 配方)。
func _needs_worker() -> bool:
	var has_fire_recipe: bool = _selected_recipe() != null
	# 装填/蓄力期间都需工人值守(装填时弦待发、需操作手,蓄力时注入工作量)。
	return has_fire_recipe and (not _shift_fired or fire_timer < CHARGE_TIME)

func _has_ammo() -> bool:
	return input_bag and input_bag.count > 0

# 机器帧推进(基类 tick 已先做值守心跳与补员维护):弩炮为 workload 驱动,
# 装填/蓄力经 worker 值守,这里负责 loading 倒计时、瞄准、firing 松弦计时与发射判定。
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
	# 装填态:弦保持松弛(progress=0),倒计时结束转入 charging 开始拉弦。
	if state == "loading":
		load_timer -= in_delta
		if load_timer <= 0:
			load_timer = 0
			state = "charging"
			progress = clampf(fire_timer / CHARGE_TIME, 0, 1)
		return
	target = find_target()
	_rotate_aim(in_delta)
	if fire_timer >= CHARGE_TIME:
		if target and is_aimed() and fire():
			state = "firing"
			fire_anim_timer = FIRE_TIME
			progress = 1
			return
		state = "ready"
		progress = 1
		return
	state = "charging"
	progress = fire_timer / CHARGE_TIME

# worker 每帧注入劳动量(delta * efficiency),累积为蓄力进度。
# 装填/松弦期间注入的工作量被忽略(操作手在端箭/松弦,不拉弦);其余状态才累计。
# 新一轮值岗(上一工人离岗后首次注入)经基类 _reset_shift() 清零发射标记并进入装填。
func _apply_workload(in_workload: float):
	if state == "firing" or state == "loading":
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
	# 新一轮值岗:先端一支新箭上弦(loading,弦保持松弛)。已蓄火力(若有)保留不丢。
	# 仅在"全新一发"(火力未开始累计)才装填端箭;若是中断续弦(0<fire_timer<CHARGE,
	# 弦上已有箭、张弦已拉一半),直接回 charging 继续拉,不重复端箭(否则弦会弹回、重复端)。
	# 已满弦(fire_timer>=CHARGE)则直接维持备战。
	if _has_ammo() and fire_timer <= 0.0:
		state = "loading"
		load_timer = LOAD_TIME
		progress = 0

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
	if not _has_ammo():
		return false
	input_bag.remove_count(1)
	var room: Room = Level.current.room
	var arrow: Arrow = Entity.create("arrow")
	# 从弩口发射:水平位置 = 弩中心 + 沿瞄准方向前移一个小偏移(弩口朝目标一侧);
	# 视觉高度由 launch_height 给出(frontend 据此把箭抬高到弩口,再画抛物线)。
	arrow.position = Vector2(axis) + aim_direction * MUZZLE_FORWARD_OFFSET
	arrow.launch_height = LAUNCH_HEIGHT
	arrow.move_speed = 10
	arrow.set_target_entity(target)
	room.add_entity(arrow)
	_shift_fired = true
	return true

# —— 攻击目标选取:按 target_preference 排序 ——

# 范围内(axis±3, 6×6)所有存活敌方,按 target_preference 排序后取第一个。
#   nearest:距离平方最小(离弩炮最近)
#   front:y 最小(越靠前,即越接近主基地推进方向;y 越负越靠前)
#   strongest:health 最高
func find_target() -> Entity:
	var room: Room = Level.current.room
	var entities: Array = room.get_entities_in_rect(Rect2(axis.x - 3, axis.y - 3, 6, 6))
	var candidates: Array[Entity] = []
	for entity: Entity in entities:
		if entity is not Enemy:
			continue
		if not entity.is_alive():
			continue
		candidates.append(entity)
	if candidates.is_empty():
		return null
	match target_preference:
		TARGET_PREF_FRONT:
			candidates.sort_custom(func(a: Entity, b: Entity) -> bool:
				return a.position.y < b.position.y)
		TARGET_PREF_STRONGEST:
			candidates.sort_custom(func(a: Entity, b: Entity) -> bool:
				return a.health > b.health)
		_:  # nearest(默认)
			candidates.sort_custom(func(a: Entity, b: Entity) -> bool:
				return _distance_sq(a.position) < _distance_sq(b.position))
	return candidates[0]

# 到弩炮的距离平方(避免开方)。
func _distance_sq(in_position: Vector2) -> float:
	var delta: Vector2 = in_position - Vector2(axis)
	return delta.length_squared()
