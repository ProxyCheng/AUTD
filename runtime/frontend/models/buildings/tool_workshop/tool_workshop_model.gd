class_name ToolWorkshopModel
extends WorkshopModel

# 工具坊表现脚本(哑脚本,不接触 backend 逻辑):由 BuildingActor 转发 state 与展示仓(bag)。
# 与车间同构 —— 直接复用车间的美术网格,只把调色板贴图换成"红橙屋顶"的那份副本
# (见 tool_workshop.tscn 里对网格节点的 material_override)。产出物(斧头/镐子)经 ItemStack
# 子节点在建筑侧方显示一小垛,跟随绑定 Bag 的数量变化增减。

@onready var content_stack: ItemStack = $content_stack

func _ready():
	super._ready()
	content_stack.per_row = 3
	content_stack.layer_count = 3
	content_stack.row_spacing = 1.05
	content_stack.layer_spacing = 1.2

# 绑定后端展示仓:物品类型与数量均由 Bag 驱动(见 ItemStack.bind)。
func bind_bag(in_bag: Bag):
	content_stack.bind(in_bag)
