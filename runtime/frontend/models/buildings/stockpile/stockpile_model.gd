class_name StockpileModel
extends Node3D

# 料堆(空底盘)的内容物显示:内容物由通用 ItemStack 组件渲染(测量→缩放→平放摞垛
# →按数量显隐),本模型脚本只负责:把 backend 转发的类型/库存在传给 ItemStack,
# 并把"库存→可见道具数"的 fill 映射语义留在这里(容量更大时每支代表一批)。
# 哑表现脚本:只吃 BuildingActor 转发的字符串/数值,不接触 backend 逻辑。

# ItemStack 是子节点,直接驱动其 set_item_type / set_count;
# 几何(每排/层数/目标长度/间距)由 _ready 配置一次即可。

# 方便获取内容物组件(类型标注为 ItemStack,便于用其 capacity)
@onready var content_stack: ItemStack = $content_stack

func _ready():
	# 配置堆垛几何:每排 4、共 3 层 → 满堆 12 支;目标长轴 0.5、间距微缝
	content_stack.per_row = 4
	content_stack.layer_count = 3
	content_stack.target_length = 0.5
	content_stack.row_spacing = 1.05
	content_stack.layer_spacing = 1.2

# BuildingActor 转发 content_type 变化:重建对应物品模型的道具池
func set_content_type(in_type: String):
	content_stack.set_item_type(in_type)

# BuildingActor 转发存量变化:按 count/capacity 折算可见道具数。
# 原有语义:有货至少 1 支,存量越多(相对容量)可见越多,0 则清空。
func set_stored_count(in_count: int, in_capacity: int):
	var visible_count: int = 0
	if in_count > 0 and in_capacity > 0:
		var fill: float = clampf(float(in_count) / float(in_capacity), 0.0, 1.0)
		visible_count = maxi(1, roundi(fill * content_stack.capacity()))
	content_stack.set_count(visible_count)
