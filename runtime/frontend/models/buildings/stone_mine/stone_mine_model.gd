class_name StoneMineModel
extends Node3D

# 石矿表现脚本(哑脚本,不接触 backend 逻辑):由 BuildingActor 转发
# state 与展示仓(bag)。产出物(石头)经 ItemStack 子节点在建筑侧方显示一小垛,
# 跟随绑定 Bag 的数量变化增减。

@onready var content_stack: ItemStack = $content_stack

func _ready():
	content_stack.per_row = 2
	content_stack.layer_count = 3
	# 石块本身很宽:每排降到 2;垛大小由 content_stack 节点的 Transform Scale 控制
	# (见 stone_mine.tscn),使整垛落在格子 [-0.5, 0.5] 内
	content_stack.row_spacing = 1.05
	content_stack.layer_spacing = 1.2

# 绑定后端展示仓:物品类型与数量均由 Bag 驱动(见 ItemStack.bind)。
func bind_bag(in_bag: Bag):
	content_stack.bind(in_bag)
