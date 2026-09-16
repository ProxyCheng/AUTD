class_name Pickaxe
extends Tool

# 镐子:车间按配方产出的手持工具(1 原木 + 1 石头 → 1 把镐子,见 CraftingWorkshop)。
# 用途:采石时加快开采 —— 对声明了 required_tool = "pickaxe" 的配方(即石矿),注入的
# 工作量按 MINE_EFFICIENCY 放大,单位时间产出更多石头;代价是耐久按注入量消耗(见 Tool)。

# 采石效率倍率:手持镐子驱动 required_tool = "pickaxe" 的配方时的注入倍率。
const MINE_EFFICIENCY: float = 2.0
# 每注入 1 单位工作量消耗的耐久点(一把镐子共可驱动 DEFAULT_MAX_DURABILITY 单位工作量)。
const WEAR_PER_WORKLOAD: float = 1.0

func _init():
	super._init()
	wear_per_workload = WEAR_PER_WORKLOAD

func work_efficiency_for(in_recipe: RecipeData) -> float:
	if in_recipe and in_recipe.required_tool == type:
		return MINE_EFFICIENCY
	return 1.0
