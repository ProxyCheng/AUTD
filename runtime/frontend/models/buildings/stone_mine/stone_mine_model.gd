class_name StoneMineModel
extends Node3D

# 石矿表现脚本(哑脚本,不接触 backend 逻辑):由 BuildingActor 转发
# state / stored_count。产出物(石头)经 ItemStack 子节点在建筑侧方显示一小垛,
# 随后端输出仓存量变化增减。

@onready var content_stack: ItemStack = $content_stack

func _ready():
	content_stack.per_row = 3
	content_stack.layer_count = 3
	content_stack.target_length = 0.5
	content_stack.row_spacing = 1.05
	content_stack.layer_spacing = 1.2
	# 本建筑专产石头
	content_stack.set_item_type("stone")

func set_stored_count(in_count: int, in_capacity: int):
	content_stack.set_count(in_count)
