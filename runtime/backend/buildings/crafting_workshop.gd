class_name CraftingWorkshop
extends Workshop

# 车间:工人注入 workload,每次产出消耗 1 原木 + 1 石头 → 生产 1 支箭(arrow)。
# 原木/石头经两只"纯需求方"输入仓由 Logistics 补货(工人在旁待料即自动补);
# 输出箭入 output_bag(纯供给方),再由 Logistics 搬到下游(如弩炮弹药箱)。
#
# 本类只声明配方(recipes):基类据配方综合推断建袋 —— 输入类型 log/stone 各建一只
# 纯需求方输入仓,输出类型 arrow 建一只纯供给方输出仓,无需手写建袋代码。
# 资源链:
#   伐木场(log)→ 车间(log 输入) 石矿(stone)→ 车间(stone 输入)
#   车间(arrow 输出)→ 弩炮(arrow 弹药)

const CONSUME_LOG: int = 1
const CONSUME_STONE: int = 1
# 产出一支箭所需的累计工作量(秒)。车间是深加工,效率低于开采;实际节拍受供需制约。
const ARROW_WORKLOAD: float = 3.0

func _ready():
	recipes = [_make_arrow_recipe()]
	super._ready()

# 声明单张配方:1 原木 + 1 石头 → 1 箭
func _make_arrow_recipe() -> RecipeData:
	var recipe := RecipeData.new()
	recipe.label = "Arrow"
	recipe.output = "arrow"
	recipe.workload_per_unit = ARROW_WORKLOAD
	var log_input := RecipeInputData.new()
	log_input.item_type = "log"
	log_input.count = CONSUME_LOG
	var stone_input := RecipeInputData.new()
	stone_input.item_type = "stone"
	stone_input.count = CONSUME_STONE
	recipe.inputs = [log_input, stone_input]
	return recipe
