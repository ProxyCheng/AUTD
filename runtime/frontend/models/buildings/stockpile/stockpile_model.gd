class_name StockpileModel
extends Node3D

# 料堆(空底盘)的内容物显示:内容物由通用 ItemStack 组件渲染(测量→缩放→平放摞垛
# →按数量显隐),本模型脚本只负责:把 backend 展示仓(bag)绑到 ItemStack,并配置几何;
# 数量按 Fill 模式映射(容量更大时每支代表一批,见 ItemStack.CountMode)。
# 哑表现脚本:只吃 BuildingActor 转发的 Bag,不接触 backend 逻辑。

# ItemStack 是子节点,直接驱动其 bind;
# 几何(每排/层数/目标长度/间距)由 _ready 配置一次即可。

# 方便获取内容物组件(类型标注为 ItemStack,便于用其 capacity)
@onready var content_stack: ItemStack = $content_stack

func _ready():
	# 配置堆垛几何:每排 4、共 3 层 → 满堆 12 支;间距微缝。
	# 垛大小由 content_stack 节点的 Transform Scale 控制(见 stockpile.tscn)。
	content_stack.per_row = 4
	content_stack.layer_count = 3
	content_stack.row_spacing = 1.05
	content_stack.layer_spacing = 1.2
	content_stack.count_mode = ItemStack.CountMode.Fill

# 绑定后端展示仓:物品类型与数量均由 Bag 驱动(见 ItemStack.bind)。
func bind_bag(in_bag: Bag):
	content_stack.bind(in_bag)
