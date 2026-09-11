class_name TreeWorkshopModel
extends WorkshopModel

# 伐木场表现脚本(哑脚本,不接触 backend 逻辑):由 BuildingActor 转发
# state 与展示仓(bag)。产出物(原木)经 ItemStack 子节点在建筑侧方显示一小垛,
# 跟随绑定 Bag 的数量变化增减。

# 砍伐震颤:每 CHOP_INTERVAL 秒一记斧击 —— 树身横向急促摇晃并迅速衰减,
# 呈现"被砍一下、抖一下"的一下一下节奏。
const CHOP_INTERVAL: float = 0.6
const CHOP_DECAY: float = 11.0
const CHOP_SHAKE_HZ: float = 3.5
const CHOP_SHAKE_AMPLITUDE: float = 0.05
const CHOP_SQUASH: float = 0.1

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

# 砍伐震颤(覆写基类默认动作):距上次斧击越近摇晃越强,随后指数衰减。
func _animate_work(_in_delta: float):
	var t: float = fmod(_phase, CHOP_INTERVAL)
	var decay: float = exp(-t * CHOP_DECAY)
	var sway: float = cos(t * CHOP_SHAKE_HZ * TAU) * decay
	_shift(Vector3(sway * CHOP_SHAKE_AMPLITUDE, 0.0, 0.0))
	_squash(decay, CHOP_SQUASH, CHOP_SQUASH * 0.5)

# 绑定后端展示仓:物品类型与数量均由 Bag 驱动(见 ItemStack.bind)。
func bind_bag(in_bag: Bag):
	content_stack.bind(in_bag)
