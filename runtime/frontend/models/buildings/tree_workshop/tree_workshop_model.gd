class_name TreeWorkshopModel
extends WorkshopModel

# 伐木场表现脚本(哑脚本,不接触 backend 逻辑):由 BuildingActor 转发
# state 与展示仓(bag)。产出物(原木)经 ItemStack 子节点在建筑侧方显示一小垛,
# 跟随绑定 Bag 的数量变化增减。

# 内容物堆叠组件(子节点,类型标注 ItemStack 便于用 capacity)
@onready var content_stack: ItemStack = $content_stack

func _ready():
	super._ready()
	# 堆垛几何:每排 3、共 3 层 → 满堆 9;微缝防 z-fight。
	# 垛大小(原木长轴)改由 content_stack 节点的 Transform Scale 控制(见 tree_workshop.tscn),
	# 原木堆需落在所属格子 [-0.5, 0.5] 内。
	content_stack.per_row = 3
	content_stack.layer_count = 3
	content_stack.row_spacing = 1.05
	content_stack.layer_spacing = 1.2

# 绑定后端展示仓:物品类型与数量均由 Bag 驱动(见 ItemStack.bind)。
func bind_bag(in_bag: Bag):
	content_stack.bind(in_bag)
