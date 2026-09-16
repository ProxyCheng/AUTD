class_name Pickaxe
extends Tool

# 镐子:车间按配方产出的手持工具(1 原木 + 1 石头 → 1 把镐子,见 ToolWorkshop)。
# 用途:采石 —— 石矿配方的 tool_bonuses 表接受 "pickaxe" 并给出注入倍率,工人持镐开采更快
# (倍率归配方,本类不含);代价是耐久按注入量消耗(见 Tool)。

# 每注入 1 单位工作量消耗的耐久点(一把镐子共可驱动 DEFAULT_MAX_DURABILITY 单位工作量)。
const WEAR_PER_WORKLOAD: float = 1.0

func _init():
	super._init()
	wear_per_workload = WEAR_PER_WORKLOAD
