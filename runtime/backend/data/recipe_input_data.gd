@tool
extends Resource
class_name RecipeInputData

# 单个配方输入条目:需要消耗的物品种类与单次数量。
# 由 RecipeData.inputs 持有,供 Workshop 校验/扣减原料。

@export
var item_type: String = ""
@export
var count: int = 1
