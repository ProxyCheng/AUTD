class_name Labor
extends Creature

# 工人随身仓:分**头顶仓**与**手仓**两只(供 frontend 分别表现)。两只都不向 Logistics 注册——
# 它们不是物流供需节点,仅随工人存取。
#   head_bag —— 头顶携带的散料(多类型仓,容量 Logistics.CARRY_CAPACITY);压弯腰的只有它。
#   hand_bag —— 手上拿着的那一件(容量 1,有状态单体如工具);取/用/还工具都认它。
# 手仓容量恒 1:手只拿得住一件 —— 工具这类"按件"物品拿多件没有意义,散料一律上头(见
# TakeFromBagTask 的入库分流)。手里那件由顶岗任务开工前的归还步骤还回容器(见 man_building.tres);
# 一直没派上用场的,空闲树也会把它卸回仓里(见 FindDepositBagTask)。
var head_bag: Bag = null
var hand_bag: Bag = null

# 空载移速:工人不带货时的基准速度(格/秒)。负重在此基准上按装载比例递减。
const BASE_MOVE_SPEED: float = 1.0

# 负重减速:头顶仓装载比例越高走得越慢(手里那件工具不计入,见 get_move_speed)。
# 空载 = BASE_MOVE_SPEED,满载(CARRY_CAPACITY 件)= BASE_MOVE_SPEED * LOADED_SPEED_FACTOR,
# 中间线性插值;系数越小减速越明显(当前满载只剩三成速度)。
const LOADED_SPEED_FACTOR: float = 0.3

func _init():
	super._init()
	move_speed = BASE_MOVE_SPEED

# 覆写 Entity.get_move_speed:按**头顶仓**装载比例减速(只从 head_bag 推算,不缓存第二份速度)。
# 压弯腰的是头顶那垛货;手里那一件(工具)不额外增加负重,故不计入。
func get_move_speed() -> float:
	var load_ratio: float = 0.0
	if is_instance_valid(head_bag) and head_bag.max_count > 0:
		load_ratio = clampf(float(head_bag.count) / float(head_bag.max_count), 0.0, 1.0)
	return move_speed * lerpf(1.0, LOADED_SPEED_FACTOR, load_ratio)

# 原 LaborBrain 的注册/注销逻辑内联:进场向调度中心注册,离场注销。
func _ready():
	head_bag = Bag.new()
	head_bag.name = "HeadBag"
	head_bag.max_count = Logistics.CARRY_CAPACITY
	add_child(head_bag)
	head_bag.owner = owner
	# 手仓容量恒 1:手只拿得住一件(有状态单体,如工具);多件散料一律上头。
	hand_bag = Bag.new()
	hand_bag.name = "HandBag"
	hand_bag.max_count = 1
	add_child(hand_bag)
	hand_bag.owner = owner
	var manager := _get_manager()
	if manager:
		manager.register_labor(self)

func _exit_tree():
	var manager := _get_manager()
	if manager:
		manager.unregister_labor(self)

# 覆写 Creature.tick:除了跑行为树,还推进**手上那件工具**(hand_bag,见 held_tool)的"未使用
# 计时" —— 工具真正驱动工作时由 ProvideWorkloadTask 清零(见 Tool.mark_used),这里只让它随时间
# 增长;于是"一直握着却没派上用场"的工具会累积到阈值,由空闲树放回仓里
# (见 FindDepositBagTask / Tool.UNUSED_PUT_AWAY_SECONDS)。
func tick(in_delta: float):
	var tool := held_tool()
	if tool:
		tool.unused_time += in_delta
	super.tick(in_delta)

# 手仓里那件工具(有状态单体);无 / 已 freed / 非 Tool 时返回 null。
func held_tool() -> Tool:
	if not is_instance_valid(hand_bag):
		return null
	var carrier: Object = hand_bag.peek_state()
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool

# 换任务 = 上一件活到此为止:还在飞的那趟立刻收工退货,免得"工人已经去干别的了,货还在往老目标飞"。
# §5.3 前端是后端的体现 —— 后端这件活停了,那段飞行表现也必须跟着停;而搬运登记在 Logistics 名下、
# 不会随树一起消失(见 ItemTransfer),所以必须在"换任务"这个唯一可靠的时机主动收掉。
# 正常路径走不到这里:叶子会一直等到搬运飞完才收工(见 BagTransferTask),故此刻在途的
# 只可能是被打断/被取消的活。换任务的两个入口是 create_tree(自己要活)与 begin_tree(被派活)。
func _cancel_in_flight_transfers():
	var logistics: Logistics = Level.current.logistics if Level.current else null
	if not logistics:
		return
	logistics.cancel_transfers_for(head_bag)
	logistics.cancel_transfers_for(hand_bag)

func begin_tree(in_tree: BehaviorTree):
	_cancel_in_flight_transfers()
	super(in_tree)

func create_tree() -> BehaviorTree:
	_cancel_in_flight_transfers()
	var manager := _get_manager()
	if manager:
		return manager.request_work(self)
	return super.create_tree()

func _get_manager() -> LaborManager:
	if not Level.current:
		return null
	return Level.current.labor_manager
