class_name Hammer
extends Tool

# 锤子:工具坊按配方产出的手持工具(1 原木 + 1 石头 → 1 把锤子,见 ToolWorkshop)。
# 用途:细作 —— 车间(arrow/cannonball)与工具坊(axe/pickaxe/hammer)配方的 tool_bonuses
# 表都接受 "hammer" 并给出注入倍率,工人持锤干活更快(倍率归配方,本类不含);代价是
# 耐久按注入量消耗(见 Tool)。

# 每注入 1 单位工作量消耗的耐久点(一把锤子共可驱动 DEFAULT_MAX_DURABILITY 单位工作量)。
const WEAR_PER_WORKLOAD: float = 1.0

func _init():
	super._init()
	wear_per_workload = WEAR_PER_WORKLOAD
