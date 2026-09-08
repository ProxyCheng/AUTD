class_name TreeWorkshopModel
extends Node3D

# 伐木场表现脚本(哑脚本,不接触 backend 逻辑):由 BuildingActor 转发
# state / stored_count。产出物(原木)经 ItemStack 子节点在建筑侧方显示一小垛,
# 随后端输出仓存量变化增减。

# 内容物堆叠组件(子节点,类型标注 ItemStack 便于用 capacity)
@onready var content_stack: ItemStack = $content_stack

func _ready():
	# 堆垛几何:每排 3、共 3 层 → 满堆 9;目标长轴 0.5,微缝防 z-fight
	content_stack.per_row = 3
	content_stack.layer_count = 3
	content_stack.target_length = 0.5
	content_stack.row_spacing = 1.05
	content_stack.layer_spacing = 1.2
	# 本建筑专产原木;后端输出仓变化经 set_stored_count 驱动显示
	content_stack.set_item_type("log")

# 由 BuildingActor 转发:后端输出仓存量变化 → 显示对应数量原木堆
func set_stored_count(in_count: int, in_capacity: int):
	content_stack.set_count(in_count)
