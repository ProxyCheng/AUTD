class_name Axe
extends Tool

# 斧头:车间按配方产出的手持工具(1 原木 + 1 石头 → 1 斧头,见 CraftingWorkshop)。
# 用途:伐木时加快砍树 —— 对声明了 required_tool = "axe" 的配方,注入的工作量按
# FELL_EFFICIENCY 放大,单位时间产出更多原木;代价是耐久按注入量消耗(见 Tool)。

# 砍树效率倍率:手持斧头驱动 required_tool = "axe" 的配方时的注入倍率。
const FELL_EFFICIENCY: float = 2.0
# 每注入 1 单位工作量消耗的耐久点(一把斧头共可驱动 DEFAULT_MAX_DURABILITY 单位工作量)。
const WEAR_PER_WORKLOAD: float = 1.0

func _init():
	super._init()
	wear_per_workload = WEAR_PER_WORKLOAD

func work_efficiency_for(in_recipe: RecipeData) -> float:
	if in_recipe and in_recipe.required_tool == type:
		return FELL_EFFICIENCY
	return 1.0
