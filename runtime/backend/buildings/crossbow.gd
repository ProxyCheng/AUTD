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
# —— 射箭几何(由弹道调试场景 arrow_traj_test 实测定值;static var 便于该场景继续试参)——
# 俯仰转轴 P(相对弩中心地面点 O):forward 沿瞄准方向前移、height 离地。
static var PIVOT_FORWARD: float = 0.16
static var PIVOT_HEIGHT: float = 0.62
# 射箭起点 S 相对转轴 P 的偏移(弩身局部系):forward 沿弩身、height 垂直弩身,随俯仰角 θ 旋转。
static var SPAWN_FORWARD: float = 0.44
static var SPAWN_HEIGHT: float = 0.09
# 弩矢水平飞行速度(世界单位/秒)。与前端弹道(Ballistic 的重力抛物线)共用同一值:
# 飞行时长 T = 水平距离 / 本速度,故目标越远飞得越久、弧顶越高。弩身预览俯仰也用它。
const ARROW_SPEED: float = 10

# —— 可覆写调参钩子 ——
# 弩炮的整条"值守/装填/蓄力/瞄准/发射"状态机对发射器本身是通用的:弹药与弹丸类型、
# 弹丸速度、装填/蓄力/开火时长、发射几何都经下列钩子取得,默认取本类常量。
# 子类(如 Cannon)只需覆写这些钩子即可复用整条状态机,无需复制 _tick_machine/_apply_workload。
# 注意:这些必须是**实例方法** —— GDScript 的 static 方法不做多态派发,若写成 static,
# 基类方法里的调用会静态绑到基类实现,子类覆写不生效。

func ammo_type() -> String:
	return "arrow"

func ammo_capacity() -> int:
	return AMMO_CAPACITY

func projectile_type() -> String:
	return "arrow"

func projectile_speed() -> float:
	return ARROW_SPEED

func charge_time() -> float:
	return CHARGE_TIME

func fire_time() -> float:
	return FIRE_TIME

func load_time() -> float:
	return LOAD_TIME

# 发射几何(转轴 P + 起点偏移 S,发射器局部系);求解见 Ballistic.spawn_offset_at/aim_pitch_for。
func pivot() -> Vector2:
	return Vector2(PIVOT_FORWARD, PIVOT_HEIGHT)

func spawn() -> Vector2:
	return Vector2(SPAWN_FORWARD, SPAWN_HEIGHT)

# 攻击范围(半边长,格子单位):寻敌区域为以弩炮所在格为中心、边长 2×ATTACK_RANGE 的正方形。
const ATTACK_RANGE: float = 3.0

# 给定离弦仰角 θ,返回射箭起点相对弩中心地面点 O 的偏移:(水平前移, 高度)。
# S = P + R(θ)·(SPAWN_FORWARD, SPAWN_HEIGHT);P = O + forward·PIVOT_FORWARD + up·PIVOT_HEIGHT。
# 求解统一在 Ballistic(弩/炮共用同一套),本静态版固定用弩炮自己的几何与弹速,
# 供前端模型(crossbow_model.set_target_position)与弹道调试场景直接读。
static func spawn_offset_at(in_pitch: float) -> Vector2:
	return Ballistic.spawn_offset_at(in_pitch, Vector2(PIVOT_FORWARD, PIVOT_HEIGHT), Vector2(SPAWN_FORWARD, SPAWN_HEIGHT))

# 求命中目标所需的离弦仰角:发射点随 θ 抬升,θ 与发射高度互相依赖,做几次不动点迭代收敛。
static func aim_pitch(in_center: Vector2, in_aim_dir: Vector2, in_target_pos: Vector2) -> float:
	return Ballistic.aim_pitch_for(in_center, in_aim_dir, in_target_pos,
		Vector2(PIVOT_FORWARD, PIVOT_HEIGHT), Vector2(SPAWN_FORWARD, SPAWN_HEIGHT), ARROW_SPEED)

# —— 配方声明:攻击 = 一次即时效果(无输出仓,消耗箭矢触发开火) ——
# 蓄满一发的蓄力由 base._apply_workload 累积 progress;满弦后由 _tick_machine 负责瞄准/发射。

func _ready():
	recipes = [_make_fire_recipe()]
	super._ready()

func _make_fire_recipe() -> RecipeData:
	var recipe := RecipeData.new()
	recipe.label = "Fire"
	recipe.output = ""
	recipe.workload_per_unit = charge_time()
	var ammo_input := RecipeInputData.new()
	ammo_input.item_type = ammo_type()
	ammo_input.count = 1
	recipe.inputs = [ammo_input]
	return recipe

# —— 攻击倾向(可观察配置)——
# 取值常量:String(全小写 snake,符合仓库"类型标识字符串"惯例)
const TARGET_PREF_NEAREST: String = "nearest"
const TARGET_PREF_FRONT: String = "front"
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
	input_bag = _make_bag("AmmoBag", ammo_type(), ammo_capacity(), true, 1)
	_bind_mirror(input_bag)

# 攻击建筑:驱动它的顶岗任务优先级=11(生产 10 再 +1),保证弩炮始终优先有人值守
func manning_priority() -> int:
	return 11

# 攻击范围半边长(格子单位),见 ATTACK_RANGE;供前端绘制范围面。
func get_attack_range() -> float:
	return ATTACK_RANGE

func is_work_done() -> bool:
	return _shift_fired

# 需要工人的条件:蓄力未完(还有活要干),或满弦但本轮尚未射出(需操作手值守待敌)。
# 发射后才暂时不需要,等松弦动画结束、fire_timer 归零再自动补位下一班。
# 顺带 _selected_recipe() 同步 active_recipe(GUI 高亮当前 Fire 配方)。
func _needs_worker() -> bool:
	var has_fire_recipe: bool = _selected_recipe() != null
	# 装填/蓄力期间都需工人值守(装填时弦待发、需操作手,蓄力时注入工作量)。
	return has_fire_recipe and (not _shift_fired or fire_timer < charge_time())

func _has_ammo() -> bool:
	return input_bag and input_bag.count > 0

# 机器帧推进(基类 tick 已先做值守心跳与补员维护):弩炮为 workload 驱动,
# 装填/蓄力经 worker 值守,这里负责 loading 倒计时、瞄准、firing 松弦计时与发射判定。
func _tick_machine(in_delta: float):
	if state == "firing":
		fire_anim_timer -= in_delta
		progress = clampf(fire_anim_timer / fire_time(), 0, 1)
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
			progress = clampf(fire_timer / charge_time(), 0, 1)
		return
	target = find_target()
	_rotate_aim(in_delta)
	if fire_timer >= charge_time():
		if target and is_aimed() and fire():
			state = "firing"
			fire_anim_timer = fire_time()
			progress = 1
			return
		state = "ready"
		progress = 1
		return
	state = "charging"
	progress = fire_timer / charge_time()

# worker 每帧注入劳动量(delta * efficiency),累积为蓄力进度。
# 装填/松弦期间注入的工作量被忽略(操作手在端箭/松弦,不拉弦);其余状态才累计。
# 新一轮值岗(上一工人离岗后首次注入)经基类 _reset_shift() 清零发射标记并进入装填。
func _apply_workload(in_workload: float):
	if state == "firing" or state == "loading":
		return
	if state == "idle":
		state = "charging"
		progress = 0
	fire_timer = minf(fire_timer + in_workload, charge_time())
	if fire_timer >= charge_time():
		state = "ready"
		progress = 1
		return
	state = "charging"
	progress = fire_timer / charge_time()

func _reset_shift():
	_shift_fired = false
	# 新一轮值岗:先端一支新箭上弦(loading,弦保持松弛)。已蓄火力(若有)保留不丢。
	# 仅在"全新一发"(火力未开始累计)才装填端箭;若是中断续弦(0<fire_timer<CHARGE,
	# 弦上已有箭、张弦已拉一半),直接回 charging 继续拉,不重复端箭(否则弦会弹回、重复端)。
	# 已满弦(fire_timer>=CHARGE)则直接维持备战。
	if _has_ammo() and fire_timer <= 0.0:
		state = "loading"
		load_timer = load_time()
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
	# 弹丸类型/弹速/发射几何全走钩子,子类(如 Cannon)覆写后无需改本方法。
	var projectile: Ballistic = Entity.create(projectile_type())
	var speed: float = projectile_speed()
	# 射出起点由俯仰几何决定:随离弦仰角 θ 绕转轴 P 旋转(高度不再固定)。
	var pitch: float = Ballistic.aim_pitch_for(Vector2(axis), aim_direction, target.position, pivot(), spawn(), speed)
	var off: Vector2 = Ballistic.spawn_offset_at(pitch, pivot(), spawn())
	projectile.position = Vector2(axis) + aim_direction * off.x
	projectile.launch_height = off.y
	projectile.move_speed = speed
	projectile.set_target_entity(target)
	room.add_entity(projectile)
	_shift_fired = true
	return true

# —— 攻击目标选取:按 target_preference 排序 ——

# 范围内(以 axis 为圆心、半径 ATTACK_RANGE 的圆形)所有存活敌方,按 target_preference 排序后取第一个。
#   nearest:距离平方最小(离弩炮最近)
#   front:y 最小(越靠前,即越接近主基地推进方向;y 越负越靠前)
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
