class_name CraftingWorkshop
extends ProducerWorkshop

# 车间:工人注入 workload,每次产出消耗 1 原木 + 1 石头 → 生产 1 支箭(arrow)。
# 原木/石头经两个"纯需求方"输入仓由 Logistics 补货(工人在旁待料即自动补);
# 输出箭入 output_bag(纯供给方),再由 Logistics 搬到下游(如弩炮弹药箱)。
#
# 相比 ProducerWorkshop 的差别:多了两个输入仓,且 _has_inputs/_consume_inputs
# 都要校验/扣减原木+石头。因此资源链为:
#   伐木场(log)→ 车间(log 输入)  石矿(stone)→ 车间(stone 输入)
#   车间(arrow 输出)→ 弩炮(arrow 弹药)

# 产出一支箭所需的累计工作量(秒)。车间是深加工,效率低于开采;实际节拍受供需制约。
func _ready():
	workload_per_unit = 3.0
	super._ready()

func _produces() -> String:
	return "arrow"

# 每次产出各消耗 1 原木、1 石头
const CONSUME_LOG: int = 1
const CONSUME_STONE: int = 1

# 输入仓(纯需求方:低于上限即求补到满,永不外供)。
var log_bag: Bag = null
var stone_bag: Bag = null

# 建原木/石头输入仓并注册到 Logistics。输入仓"只进不出":
# preferred_min = preferred_max = max_count → 低于 max 即请求补仓,永不外供。
func _setup_bags():
	log_bag = _make_input_bag("LogBag", "log")
	stone_bag = _make_input_bag("StoneBag", "stone")

func _make_input_bag(in_name: String, in_item_type: String) -> Bag:
	var bag := Bag.new()
	bag.name = in_name
	bag.item_type = in_item_type
	bag.max_count = output_capacity
	bag.preferred_min_count = output_capacity
	bag.preferred_max_count = output_capacity
	bag.access_position = Vector2(axis)
	add_child(bag)
	bag.owner = owner
	_register_input_bag(bag)
	return bag

# 输入齐备:原木、石头各至少一件(单次产出所需)。
func _has_inputs() -> bool:
	return (log_bag and log_bag.count >= CONSUME_LOG) \
			and (stone_bag and stone_bag.count >= CONSUME_STONE)

# 实际扣减一件产出所需:原木、石头各一件;不足则失败(返回 false)。
func _consume_inputs() -> bool:
	if not log_bag or not stone_bag:
		return false
	if log_bag.count < CONSUME_LOG or stone_bag.count < CONSUME_STONE:
		return false
	log_bag.remove_count(CONSUME_LOG)
	stone_bag.remove_count(CONSUME_STONE)
	return true

func _exit_tree():
	_unregister_input_bags()
	super._exit_tree()

func _register_input_bag(in_bag: Bag):
	var logistics: Logistics = _get_logistics()
	if logistics:
		logistics.register_bag(in_bag)

func _unregister_input_bags():
	var logistics: Logistics = _get_logistics()
	if not logistics:
		return
	if log_bag:
		logistics.unregister_bag(log_bag.id)
	if stone_bag:
		logistics.unregister_bag(stone_bag.id)
