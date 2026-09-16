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
# 工具加速表 { 工具类型: 注入倍率 }:空表 = 本配方无需工具(空手即正常,倍率 1.0);非空表 =
# 表中每种类型都是本配方接受的工具,其值为该工具带来的注入倍率(持表内任意一件即加速,多件在手
# 取倍率最高者)。倍率放配方而非工具类:同一工具在不同配方可有不同加成,新增更强的工具变体
# (如铁斧)只需改表 + 加一个 Tool 子类,AI 侧零改动(见 ProvideWorkloadTask)。
@export
var tool_bonuses: Dictionary[String, float] = {}   # { 工具类型: 注入倍率 }
@export
var inputs: Array[RecipeInputData] = []  # 单件产物消耗的原料清单(可空)
