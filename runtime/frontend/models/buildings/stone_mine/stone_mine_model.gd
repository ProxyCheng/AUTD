class_name StoneMineModel
extends WorkshopModel

# 石矿表现脚本(哑脚本,不接触 backend 逻辑):由 BuildingActor 转发
# state 与展示仓(bag)。产出物(石头)经 ItemStack 子节点在建筑侧方显示一小垛,
# 跟随绑定 Bag 的数量变化增减。

# 采石冲击:每 THUD_INTERVAL 秒一记重击 —— 整机向下一沉并压扁(变矮变宽),
# 随后较快回弹;比伐木更沉、更慢,贴合凿击岩石的顿挫感。
const THUD_INTERVAL: float = 1.0
const THUD_DECAY: float = 7.0
const THUD_SINK: float = 0.035
const THUD_SQUASH: float = 0.16
const THUD_WIDEN: float = 0.09

@onready var content_stack: ItemStack = $content_stack

func _ready():
	super._ready()
	content_stack.per_row = 2
	content_stack.layer_count = 3
	# 石块本身很宽:每排降到 2;垛大小由 content_stack 节点的 Transform Scale 控制
	# (见 stone_mine.tscn),使整垛落在格子 [-0.5, 0.5] 内
	content_stack.row_spacing = 1.05
	content_stack.layer_spacing = 1.2

# 采石冲击(覆写基类默认动作):距上次重击越近下沉/压扁越强,随后指数回弹。
func _animate_work(_in_delta: float):
	var t: float = fmod(_phase, THUD_INTERVAL)
	var decay: float = exp(-t * THUD_DECAY)
	_shift(Vector3(0.0, -THUD_SINK * decay, 0.0))
	_squash(decay, THUD_SQUASH, THUD_WIDEN)

# 绑定后端展示仓:物品类型与数量均由 Bag 驱动(见 ItemStack.bind)。
func bind_bag(in_bag: Bag):
	content_stack.bind(in_bag)
