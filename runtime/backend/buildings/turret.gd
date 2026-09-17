@abstract
class_name Turret
extends AttackBuilding

# 炮塔类攻击建筑基类:弩炮(crossbow)与火炮(cannon)共用同一套"工人驱动"机器 ——
# 值守/装填/蓄力/瞄准/发射状态机、弹药仓与 Fire 配方(有输入无输出:消耗弹药,产出一次
# 发射这一即时效果),以及两塔共用的发射几何。与武器无关的骨架收在本类,具体弹种/弹速/
# 时序由子类经下列钩子给出(见 Crossbow/Cannon)。
#
# 与前端 TurretModel 一一对应:后端 Turret(状态机 + 调参钩子) ↔ 前端 TurretModel
# (水平转向/俯仰/备弹垛 + 动画钩子),两侧都以"子类只给参数与动画"为约定。

# —— 发射几何(由弹道调试场景 arrow_traj_test 实测定值;static var 便于该场景继续试参)——
# 俯仰转轴 P(相对炮塔中心地面点 O):forward 沿瞄准方向前移、height 离地。
static var PIVOT_FORWARD: float = 0.16
static var PIVOT_HEIGHT: float = 0.62
# 发射起点 S 相对转轴 P 的偏移(炮塔局部系):forward 沿炮口前向、height 垂直炮口前向,随俯仰角 θ 旋转。
static var SPAWN_FORWARD: float = 0.44
static var SPAWN_HEIGHT: float = 0.09

# —— 可覆写调参钩子 ——
# 炮塔的整条"值守/装填/蓄力/瞄准/发射"状态机对发射器本身是通用的:弹药与弹丸类型、
# 弹丸速度、装填/蓄力/开火时长、发射几何都经下列钩子取得。本类为抽象基类,具体取值
# 一律由子类给出(见 Crossbow/Cannon);子类只需实现这些钩子即可复用整条状态机,
# 无需复制 _tick_machine/_apply_workload。
# 注意:这些必须是**实例方法** —— GDScript 的 static 方法不做多态派发,若写成 static,
# 基类方法里的调用会静态绑到基类实现,子类覆写不生效。

@abstract
func ammo_type() -> String

@abstract
func ammo_capacity() -> int

@abstract
func projectile_type() -> String

@abstract
func projectile_speed() -> float

@abstract
func charge_time() -> float

@abstract
func fire_time() -> float

@abstract
func load_time() -> float

# 发射几何(转轴 P + 起点偏移 S,发射器局部系);供 frontend 的 Trajectory 求解俯仰/起点。
# 默认取本类共用静态值;某型武器需单独标定发射几何时覆写本方法即可,无需改基类。
func pivot() -> Vector2:
	return Vector2(PIVOT_FORWARD, PIVOT_HEIGHT)

func spawn() -> Vector2:
	return Vector2(SPAWN_FORWARD, SPAWN_HEIGHT)

# —— 配方声明:攻击 = 一次即时效果(无输出仓,消耗弹药触发开火) ——
# 蓄满一发的蓄力由 base._apply_workload 累积 progress;蓄满后由 _tick_machine 负责瞄准/发射。

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

var fire_timer: float = 0
var fire_anim_timer: float = 0
# 装填计时:工人到位进入 loading 后倒计时;归零转为 charging(开始蓄力),再累计蓄力。
var load_timer: float = 0
# 上弦/装弹进度([0,1],契约同 progress):loading 期间由 load_timer 折算,供前端驱动
# "从备弹垛取一发"的表现(弩:端箭上弦;炮:炮弹入膛)。与 progress 分开 —— progress 表示
# 蓄力工作量(还要喂头顶工作量条与配方行),本值只描述端箭/装弹准备这一段,不计入配方进度。
var load_progress: float = 0:
	get:
		return load_progress
	set(in_progress):
		if is_equal_approx(in_progress, load_progress):
			return
		load_progress = in_progress
		load_progress_changed.emit()
signal load_progress_changed()

# 弹药输入仓(弹种由子类钩子给出,纯需求方)。基类 _ready → _setup_bags 创建并注册;作展示镜像
# (stored_count 镜像 input_bag.count)。前端展示时会再扣掉"已在武器内的一发"。
var input_bag: Bag
var _shift_fired: bool = false  # 本班值岗是否已射出一发(完成一次生产)

# 炮塔档位加成:顶岗与补货都比同等 priority 的普通作坊高一档(见 manning_priority/_setup_bags)。
# 基准值取实例 priority(1-9,默认 5),故"同档位下炮塔始终优先有人值守、优先补弹"。
const TURRET_MANNING_EDGE: int = 1

# 无输出仓配方:只建弹药输入仓并指定其为展示镜像(不调用 super,基类默认会按
# _produces() 建输出仓,而炮塔无配方产出)。
# 弹药仓是纯需求方,补货优先级与顶岗同档(+TURRET_MANNING_EDGE):炮塔补弹优先于普通作坊补料。
func _setup_bags():
	input_bag = _make_bag("AmmoBag", ammo_type(), ammo_capacity(), true, priority + TURRET_MANNING_EDGE)
	_bind_mirror(input_bag)

# 攻击建筑:驱动它的顶岗任务优先级 = 本机 priority + TURRET_MANNING_EDGE(比普通作坊高一档),
# 保证炮塔始终优先有人值守
func manning_priority() -> int:
	return priority + TURRET_MANNING_EDGE

func is_work_done() -> bool:
	return _shift_fired

# 需要工人的条件:蓄力未完(还有活要干),或蓄满但本轮尚未射出(需操作手值守待敌)。
# 发射后才暂时不需要,等开火动画结束、fire_timer 归零再自动补位下一班。
# 顺带 _selected_recipe() 同步 active_recipe(GUI 高亮当前 Fire 配方)。
func _needs_worker() -> bool:
	var has_fire_recipe: bool = _selected_recipe() != null
	# 装填/蓄力期间都需工人值守(装填时弹药待发、需操作手,蓄力时注入工作量)。
	return has_fire_recipe and (not _shift_fired or fire_timer < charge_time())

func _has_ammo() -> bool:
	return input_bag and input_bag.count > 0

# 机器帧推进(基类 tick 已先做值守心跳与补员维护):炮塔为 workload 驱动,
# 装填/蓄力经 worker 值守,这里负责 loading 倒计时、瞄准、firing 开火计时与发射判定。
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
	# 装填态:弹药未就位(progress 保持 0),取弹进度走 load_progress;倒计时结束转入 charging。
	# load_progress 先落到 1 再换状态,前端得以把取弹动画收在终点。
	if state == "loading":
		load_timer -= in_delta
		load_progress = clampf(1.0 - load_timer / maxf(load_time(), 0.0001), 0.0, 1.0)
		if load_timer <= 0:
			load_timer = 0
			load_progress = 1.0
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
	# 蓄力只由 _begin_loading 起头(新一班值岗 / 空弦收到工作量)。空弦(idle)不在这里转
	# charging —— 那会跳过上弦:前端把"武器里那发"当成已挂上弦而显示出来,之后真正装填时
	# 看着就是"箭先在弦上闪一下,再飞上去"。
	if state == "charging":
		progress = fire_timer / charge_time()

# worker 每帧注入劳动量(delta * efficiency),累积为蓄力进度。
# 装填/开火期间注入的工作量被忽略(操作手在装填/开火,不注入蓄力);其余状态才累计。
# 新一轮值岗(上一工人离岗后首次注入)经基类 _reset_shift() 清零发射标记并进入装填。
func _apply_workload(in_workload: float):
	if state == "firing" or state == "loading":
		return
	if state == "idle":
		# 空弦收到工作量:先从垛上弦(loading);这一帧的工作量随装填一并被忽略。
		if _begin_loading():
			return
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
	# 新一轮值岗:先装填一发(loading,未开始蓄力)。已蓄力进度(若有)保留不丢。
	# 仅在"全新一发"(蓄力未开始累计)才进入装填;若是中断续力(0<fire_timer<charge_time(),
	# 已装填且蓄力进行到一半),直接回 charging 继续,不重复装填(否则装填动作会重头再来)。
	# 已蓄满(fire_timer>=charge_time())则直接维持备战。
	_begin_loading()

# 进入装填(端箭上弦 / 装弹上膛):空弦(未开始蓄力)且弹药仓有货时才需要。返回是否真的进入。
# 空弦必须先走这一步再蓄力 —— 直接进 charging 会让前端把"武器里那发"当成已挂上弦显示出来,
# 而垛又还没少显示那一支,于是同一支箭被画两次;随后真正装填时看着就是"先闪一下"。
func _begin_loading() -> bool:
	if not _has_ammo() or fire_timer > 0.0:
		return false
	# load_progress 先归零再换状态:前端在 set_state("loading") 那一帧就已拿到 0,
	# 取弹起点与"垛少显示一支"同帧生效,不会先闪在弦位/膛口。
	load_progress = 0.0
	state = "loading"
	load_timer = load_time()
	progress = 0
	return true

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
	# 投射物只做平面运动:起点沿瞄准方向前移到炮口(俯仰/抛物线由 frontend 的 Trajectory 模拟)。
	projectile.position = Vector2(axis) + aim_direction * (pivot().x + spawn().x)
	projectile.move_speed = speed
	projectile.set_target_entity(target)
	room.add_entity(projectile)
	_shift_fired = true
	return true
