class_name Labor
extends Creature

# 工人随身仓:携带量的唯一来源(供 frontend 头顶表现)。不向 Logistics 注册——它不是
# 物流供需节点,仅随工人存取。
# 它是**多类型仓**:搬运的散料各占一格,手上那把工具(有状态单体)另占一格。工具占的那格
# 由顶岗任务开工前的归还步骤还回容器(见 man_building.tres);一直没派上用场的,空闲树也会
# 把它卸回仓里(见 FindDepositBagTask)。
var carried_bag: Bag = null

# 空载移速:工人不带货时的基准速度(格/秒)。负重在此基准上按装载比例递减。
const BASE_MOVE_SPEED: float = 1.0

# 负重减速:随身仓装载比例越高走得越慢。
# 空载 = BASE_MOVE_SPEED,满载(CARRY_CAPACITY 件)= BASE_MOVE_SPEED * LOADED_SPEED_FACTOR,
# 中间线性插值;系数越小减速越明显(当前满载只剩三成速度)。
const LOADED_SPEED_FACTOR: float = 0.3

func _init():
	super._init()
	move_speed = BASE_MOVE_SPEED

# 覆写 Entity.get_move_speed:按随身仓装载比例减速(从 carried_bag 推算,不缓存第二份速度)。
func get_move_speed() -> float:
	var load_ratio: float = 0.0
	if is_instance_valid(carried_bag) and carried_bag.max_count > 0:
		load_ratio = clampf(float(carried_bag.count) / float(carried_bag.max_count), 0.0, 1.0)
	return move_speed * lerpf(1.0, LOADED_SPEED_FACTOR, load_ratio)

# 原 LaborBrain 的注册/注销逻辑内联:进场向调度中心注册,离场注销。
func _ready():
	carried_bag = Bag.new()
	carried_bag.name = "CarriedBag"
	carried_bag.max_count = Logistics.CARRY_CAPACITY
	add_child(carried_bag)
	carried_bag.owner = owner
	var manager := _get_manager()
	if manager:
		manager.register_labor(self)

func _exit_tree():
	var manager := _get_manager()
	if manager:
		manager.unregister_labor(self)

# 覆写 Creature.tick:除了跑行为树,还推进手上工具的"未使用计时" —— 工具真正驱动工作时由
# ProvideWorkloadTask 清零(见 Tool.mark_used),这里只让它随时间增长;于是"一直握着却没派上
# 用场"的工具会累积到阈值,由空闲树放回仓里(见 FindDepositBagTask / Tool.UNUSED_PUT_AWAY_SECONDS)。
func tick(in_delta: float):
	var tool := held_tool()
	if tool:
		tool.unused_time += in_delta
	super.tick(in_delta)

# 随身仓里那件工具(有状态单体);无 / 已 freed / 非 Tool 时返回 null。
func held_tool() -> Tool:
	if not is_instance_valid(carried_bag):
		return null
	var carrier: Object = carried_bag.peek_state()
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool

func create_tree() -> BehaviorTree:
	var manager := _get_manager()
	if manager:
		return manager.request_work(self)
	return super.create_tree()

func _get_manager() -> LaborManager:
	if not Level.current:
		return null
	return Level.current.labor_manager
