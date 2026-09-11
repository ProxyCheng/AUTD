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
# 采石碎屑粒子(场景节点 %debris):每记重击喷一次。
@onready var _debris: GPUParticles3D = %debris
# 已喷过的重击序号(相位/THUD_INTERVAL 的整数部分),用于每记只喷一次
var _burst_index: int = -1

func _ready():
	super._ready()
	content_stack.per_row = 2
	content_stack.layer_count = 3
	# 石块本身很宽:每排降到 2;垛大小由 content_stack 节点的 Transform Scale 控制
	# (见 stone_mine.tscn),使整垛落在格子 [-0.5, 0.5] 内
	content_stack.row_spacing = 1.05
	content_stack.layer_spacing = 1.2

# 进入运转时复位重击序号,使开工第一记立即喷碎屑。
func set_state(in_state: String):
	super.set_state(in_state)
	if in_state == "working":
		_burst_index = -1

# 采石冲击(覆写基类默认动作):距上次重击越近下沉/压扁越强,随后指数回弹;
# 每记重击(相位跨过 THUD_INTERVAL 的整数倍)喷一次碎屑。
func _animate_work(_in_delta: float):
	var t: float = fmod(_phase, THUD_INTERVAL)
	var decay: float = exp(-t * THUD_DECAY)
	_shift(Vector3(0.0, -THUD_SINK * decay, 0.0))
	_squash(decay, THUD_SQUASH, THUD_WIDEN)
	var index: int = int(_phase / THUD_INTERVAL)
	if index != _burst_index:
		_burst_index = index
		if _debris:
			_debris.restart()

# 绑定后端展示仓:物品类型与数量均由 Bag 驱动(见 ItemStack.bind)。
func bind_bag(in_bag: Bag):
	content_stack.bind(in_bag)
