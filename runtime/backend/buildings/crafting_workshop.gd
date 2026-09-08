class_name CraftingWorkshop
extends Workshop

# 车间:工人注入 workload,每次产出消耗 1 原木 + 1 石头 → 生产 1 支箭(arrow)。
# 原木/石头经两个"纯需求方"输入仓由 Logistics 补货(工人在旁待料即自动补);
# 输出箭入 output_bag(纯供给方),再由 Logistics 搬到下游(如弩炮弹药箱)。
#
# 相比基类默认配方(单输出仓、无输入)的差别:多了两个输入仓,且 _has_inputs/
# _consume_inputs 都要校验/扣减原木+石头。因此资源链为:
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

# 先让基类建输出仓(按 _produces()),再补两只纯需求方输入仓。输入仓"只进不出":
# preferred_min = preferred_max = max_count → 低于 max 即请求补仓,永不外供。
func _setup_bags():
	super._setup_bags()
	log_bag = _make_bag("LogBag", "log", output_capacity, true)
	stone_bag = _make_bag("StoneBag", "stone", output_capacity, true)

# 输入齐备:原木、石头各至少一件(单次产出所需)。
func _has_inputs() -> bool:
	return (log_bag and log_bag.count >= CONSUME_LOG) \
			and (stone_bag and stone_bag.count >= CONSUME_STONE)

# 车间有三个 Bag(原木输入/石头输入/箭输出),容量条显示占用最满的那个。
func occupancy_fill() -> float:
	var best: float = 0.0
	for bag: Bag in [log_bag, stone_bag, output_bag]:
		if bag == null or bag.max_count <= 0:
			continue
		best = maxf(best, clampf(float(bag.count) / float(bag.max_count), 0.0, 1.0))
	return best

# 实际扣减一件产出所需:原木、石头各一件;不足则失败(返回 false)。
func _consume_inputs() -> bool:
	if not log_bag or not stone_bag:
		return false
	if log_bag.count < CONSUME_LOG or stone_bag.count < CONSUME_STONE:
		return false
	log_bag.remove_count(CONSUME_LOG)
	stone_bag.remove_count(CONSUME_STONE)
	return true
