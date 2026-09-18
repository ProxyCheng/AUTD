class_name CraftingWorkshop
extends Workshop

# 车间:工人注入 workload,按当前优先配方生产 ——
#   1 原木 + 1 石头 → 1 支箭(arrow)
#   5 石头          → 1 发炮弹(cannonball)
# 原料经"纯需求方"输入仓由 Logistics 补货(工人在旁待料即自动补);产出按配方 output
# 路由到对应类型的"纯供给方"输出仓,再由 Logistics 搬到下游(弩炮/火炮的弹药箱)。
#
# 本类只声明配方(recipes):基类据配方综合推断建袋 —— 输入类型 log/stone 各建一只
# 纯需求方输入仓,产出类型 arrow/cannonball 各建一只纯供给方输出仓,无需手写建袋代码。
# 配方按数组顺序决定优先级(越靠前越优先),GUI 可拖动排序;箭在前,故默认先产箭,
# 要转产炮弹需在检视面板把炮弹配方拖到箭前面(排在前面的可行配方会一直抢先生产,
# 不提升优先级炮弹就永远排不上)。
# 两条配方的 tool_bonuses 都声明 { "hammer": 2.0 }:工人会先去有锤子的容器取一把再开工
# (见 man_building.tres);地图没有锤子时退化为空手效率(常数 0.1),持锤则注入量翻倍。
# 资源链:
#   伐木场(log)→ 车间(log 输入) 石矿(stone)→ 车间(stone 输入)
#   车间(arrow 输出)→ 弩炮(arrow 弹药) / 车间(cannonball 输出)→ 火炮(cannonball 弹药)
#   工具坊(axe/pickaxe 输出)→ 工人手持工具(Tool)

const CONSUME_LOG: int = 1
const CONSUME_STONE: int = 1
# 产出一支箭所需的累计工作量(秒)。车间是深加工,效率低于开采;实际节拍受供需制约。
const ARROW_WORKLOAD: float = 3.0
# 炮弹配方:5 石头 → 1 发炮弹;比制箭更耗时(更重的深加工)。
const CANNONBALL_STONE: int = 5
const CANNONBALL_WORKLOAD: float = 4.0

func _ready():
	recipes = [_make_arrow_recipe(), _make_cannonball_recipe()]
	super._ready()

# 声明单张配方:1 原木 + 1 石头 → 1 箭
func _make_arrow_recipe() -> RecipeData:
	var recipe := RecipeData.new()
	recipe.label = "Arrow"
	recipe.output = "arrow"
	recipe.workload_per_unit = ARROW_WORKLOAD
	recipe.tool_bonuses = {"hammer": 2.0}
	var log_input := RecipeInputData.new()
	log_input.item_type = "log"
	log_input.count = CONSUME_LOG
	var stone_input := RecipeInputData.new()
	stone_input.item_type = "stone"
	stone_input.count = CONSUME_STONE
	recipe.inputs = [log_input, stone_input]
	return recipe

# 声明单张配方:5 石头 → 1 发炮弹
func _make_cannonball_recipe() -> RecipeData:
	var recipe := RecipeData.new()
	recipe.label = "Cannonball"
	recipe.output = "cannonball"
	recipe.workload_per_unit = CANNONBALL_WORKLOAD
	recipe.tool_bonuses = {"hammer": 2.0}
	var stone_input := RecipeInputData.new()
	stone_input.item_type = "stone"
	stone_input.count = CANNONBALL_STONE
	recipe.inputs = [stone_input]
	return recipe
