@tool
extends Resource
class_name RecipeData

# 一张配方:描述一次"生产"需要哪些输入、产出什么、每件耗时。
# Workshop 持有 Array[RecipeData] 作为其配方列表,按数组顺序决定执行优先级
# (越靠前越优先执行);GUI 可通过 Workshop.move_recipe(...) 调整该顺序。
#
# 三种形态(与 Workshop 基类文档注释对应):
#   * 无输入有输出:伐木场/石矿(采天然资源 → 输出仓);
#   * 有输入有输出:车间(耗原木+石头 → 箭);
#   * 有输入无输出:瞬时效果机器(弩炮耗箭 → 开火),output 为空字符串。
# 空配方(output 与 inputs 都为空)作占位/无配方档,执行时跳过。

@export
var label: String = ""            # GUI 显示名(如 "Log"/"Arrow"/"Arrow v2")
@export
var output: String = ""           # 产出物类型;"" = 无输出仓(瞬时效果/占位)
@export
var output_count: int = 1         # 单件产物数量(如 "2x+3y->2z");连续产出时每周期产出件数
@export
var workload_per_unit: float = 2.0  # 产出一件所需累计工作量(秒,工人效率=1)
@export
var required_tool: String = ""    # 执行本配方所需的工具类型(如 "axe");"" = 无需工具,空手可做
@export
var inputs: Array[RecipeInputData] = []  # 单件产物消耗的原料清单(可空)
