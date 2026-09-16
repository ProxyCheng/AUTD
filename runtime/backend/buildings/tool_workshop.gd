class_name ToolWorkshop
extends Workshop

# 工具坊:工人注入 workload,按当前优先配方生产手持工具 ——
#   1 原木 + 1 石头 → 1 把斧头(axe)
#   1 原木 + 1 石头 → 1 把镐子(pickaxe)
# 原料经"纯需求方"输入仓由 Logistics 补货(工人在旁待料即自动补);产出按配方 output
# 路由到对应类型的"纯供给方"输出仓,再由 Logistics 搬到工人手上。
#
# 本类只声明配方(recipes):基类据配方综合推断建袋 —— 输入类型 log/stone 各建一只
# 纯需求方输入仓,产出类型 axe/pickaxe 各建一只纯供给方输出仓,无需手写建袋代码。
# 配方按数组顺序决定优先级(越靠前越优先),GUI 可拖动排序;斧头在前,故默认先产斧头,
# 要转产镐子需在检视面板把镐子配方拖到斧头前面(输入同为 log+stone 的配方会被
# 排在前面的那个一直抢走,不提升优先级就永远不产)。
# 资源链:
#   伐木场(log)→ 工具坊(log 输入) 石矿(stone)→ 工具坊(stone 输入)
#   工具坊(axe/pickaxe 输出)→ 工人手持工具(Tool)

const CONSUME_LOG: int = 1
const CONSUME_STONE: int = 1
# 斧头配方:1 原木 + 1 石头 → 1 把斧头;比采伐更费工(更大的深加工件)。
const AXE_WORKLOAD: float = 4.0
# 镐子配方:1 原木 + 1 石头 → 1 把镐子;与斧头同工(同规格的深加工件)。
const PICKAXE_WORKLOAD: float = 4.0

func _ready():
	recipes = [_make_axe_recipe(), _make_pickaxe_recipe()]
	super._ready()

# 声明单张配方:1 原木 + 1 石头 → 1 把斧头
func _make_axe_recipe() -> RecipeData:
	var recipe := RecipeData.new()
	recipe.label = "Axe"
	recipe.output = "axe"
	recipe.workload_per_unit = AXE_WORKLOAD
	var log_input := RecipeInputData.new()
	log_input.item_type = "log"
	log_input.count = CONSUME_LOG
	var stone_input := RecipeInputData.new()
	stone_input.item_type = "stone"
	stone_input.count = CONSUME_STONE
	recipe.inputs = [log_input, stone_input]
	return recipe

# 声明单张配方:1 原木 + 1 石头 → 1 把镐子
func _make_pickaxe_recipe() -> RecipeData:
	var recipe := RecipeData.new()
	recipe.label = "Pickaxe"
	recipe.output = "pickaxe"
	recipe.workload_per_unit = PICKAXE_WORKLOAD
	var log_input := RecipeInputData.new()
	log_input.item_type = "log"
	log_input.count = CONSUME_LOG
	var stone_input := RecipeInputData.new()
	stone_input.item_type = "stone"
	stone_input.count = CONSUME_STONE
	recipe.inputs = [log_input, stone_input]
	return recipe
