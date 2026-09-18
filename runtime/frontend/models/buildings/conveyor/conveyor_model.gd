class_name ConveyorModel
extends Node3D

# 传送带表现模型(哑表现脚本,不接 backend 逻辑)。
#
# 带面运动由骨架循环动画驱动:12 根横条合并成单个蒙皮网格,一根横条一根骨
# (见 conveyor.blend 的 ConveyorRig / cleats),动画 ConveyorRig|Run 由
# %AnimationPlayer 播放。
#
# 循环机制:一个动画周期恰好走过"一个横条间距",跑完一圈后每根横条正好落在
# 下一根的位置;12 根完全同构 ⇒ 姿态集合重合 ⇒ 无缝循环,且关键帧量只有
# "跑满整圈"方案的 1/12。故本动画必须整体循环播放,不能当单次动作播。
#
# 尺度:conveyor.tscn 的根节点把美术统一缩到 1 格(带面长 1 格、宽 1 格),所以带面的
# 世界线速度要乘上根节点缩放。这里用自身 scale 推算,避免与场景里的缩放两处硬编码脱节。
#
# 朝向:根节点同时绕 Y 转 +90°,把带面行进方向(模型 +X)对到模型正面(-Z),
# 与 BuildingActor.look_at 的约定一致 —— 于是 data.direction 就是输出方向。
#
# 节点约定(见 conveyor.tscn,%AnimationPlayer 已在场景内标 unique_name_in_owner):
#   %AnimationPlayer → ConveyorRig|Run

const ANIM_NAME: StringName = &"ConveyorRig|Run"

# 动画一个周期的时长(秒):Blender 侧 24 帧 @24fps。
const CYCLE_SECONDS: float = 1.0

# 一个周期内带面在"模型自身空间"走过的距离(m):12 根横条等分环路后的间距。
const CYCLE_DISTANCE: float = 0.342124

# 动画在模型自身空间里的基准带面线速度(m/s),即 speed_scale = 1 时的速度。
const ANIM_BASE_SPEED: float = CYCLE_DISTANCE / CYCLE_SECONDS

# 默认带面线速度(m/s,世界空间)= 一格 1 单位 / backend Conveyor.CELL_TRAVEL_SECONDS,
# 即那个常量的倒数。后端改带速时这里要跟着改。
const DEFAULT_SPEED: float = 0.5

# 唯一名解析的播放器:FBX 自带,已由 conveyor.tscn 标为 unique_name_in_owner。
@onready var _animation: AnimationPlayer = %AnimationPlayer
# 承载物垛(conveyor.tscn 里已就位):显示在途那一件,随 progress 沿带面滑动。
@onready var _hold_stack: ItemStack = $hold_stack

# —— 承载物几何(模型局部空间)——
# 带面在模型局部空间里沿 +X 行进(见 conveyor.tscn 根节点的缩放/旋转),故入口在 -X 侧、
# 出口在 +X 侧。数值取自带面实测 AABB 的**真实两端**,不能随手内缩:相邻两条带的端头在
# 世界空间里落在同一格边上,所以"A 的终点"与"B 的起点"必须用各自的真实端点才会重合 ——
# 一旦内缩半个货长,跨带时物品就会往前跳一整个货长。
const BELT_INPUT_X: float = -0.963258
const BELT_OUTPUT_X: float = 0.986742
const BELT_TOP_Y: float = 0.1877

# 货物期望长度(世界单位,约 4/5 格)。各道具原生尺寸差很多(箭 vs 原木),不归一化
# 会让原木盖住整条带、箭小得看不见,故按类型统一缩到这个长度。
const ITEM_LENGTH: float = 0.8

var _bag: Bag = null

func _ready():
	# 首尾姿态集合相接(见文件头"循环机制"),故用 LOOP_LINEAR 整体循环。
	var animation: Animation = _animation.get_animation(ANIM_NAME)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR
	set_speed(DEFAULT_SPEED)

# 设置带面线速度(m/s,世界空间):按世界空间基准速度换算成播放速率;
# 传 0 则暂停(横条停在原地)。
# 由建筑 Actor 经 has_method 探测调用(可选表现接口,同 §5.4 的 state 契约)。
func set_speed(in_speed: float):
	_animation.speed_scale = in_speed / _world_base_speed()
	if is_zero_approx(in_speed):
		_animation.pause()
	elif not _animation.is_playing():
		_animation.play(ANIM_NAME)

# 世界空间基准带面速度:动画自身空间的速度 × 根节点缩放(本场景把美术缩到 1 格)。
func _world_base_speed() -> float:
	return ANIM_BASE_SPEED * absf(scale.x)

# 绑定 backend 展示仓(= Conveyor.bag,在途那一件),由 BuildingActor 转发(§5.5)。
# 解绑时 actor 会传 null。
func bind_bag(in_bag: Bag):
	if is_instance_valid(_bag) and _bag.item_type_changed.is_connected(_on_bound_type_changed):
		_bag.item_type_changed.disconnect(_on_bound_type_changed)
	_bag = in_bag
	_hold_stack.bind(in_bag)
	# 先 bind 再连:ItemStack 自己也连了 item_type_changed,让它先重建道具,本处再改缩放。
	if is_instance_valid(_bag) and not _bag.item_type_changed.is_connected(_on_bound_type_changed):
		_bag.item_type_changed.connect(_on_bound_type_changed)
	_normalize_item_scale()

# 运输进度 [0,1]:把货沿带面从入口滑到出口。0 = 刚取到(入口端),1 = 到站(出口端)。
# 用带面真实端点做行程(见 BELT_INPUT_X 的注释)—— 相邻带子的端点在格边上重合,
# 故跨带时物品位置连续,不会跳。
func set_progress(in_progress: float):
	if not is_instance_valid(_hold_stack):
		return
	_hold_stack.position.x = lerpf(BELT_INPUT_X, BELT_OUTPUT_X, clampf(in_progress, 0.0, 1.0))

# 货物类型变了(取到新货 / 投出后清空)→ 按新类型重新归一尺寸。
func _on_bound_type_changed():
	_normalize_item_scale()

# 按当前货物类型把垛缩放到统一的世界长度(见 ITEM_LENGTH)。
# 垛在根节点的局部空间里,根节点是统一缩放(见 conveyor.tscn:美术本身长宽同尺度 1.95,
# 故 1/1.95 一次压成"长 1 格、宽 1 格")。世界长度 = 道具原生长轴 × 垛缩放 × 根缩放,
# 故先把根缩放除掉,换算出垛该用的本地缩放。
# 不变式:美术必须保持"长宽同尺度",否则根节点就得非均匀缩放,物品会被横向拉变形。
func _normalize_item_scale():
	if not is_instance_valid(_hold_stack):
		return
	var type: String = _bound_type()
	if type.is_empty() or not ItemStack.ITEM_MODEL_SCENES.has(type):
		return
	var root_scale: float = absf(scale.x)
	if root_scale <= 0.0:
		return
	var s: float = (ITEM_LENGTH / root_scale) / maxf(ItemStack.long_axis_of(type), 0.0001)
	_hold_stack.scale = Vector3(s, s, s)

# 当前该显示的类型:优先看仓声明的 item_type(传送带取到货时会写它),否则退回按件状态
# 载体的 type —— 有状态物品的类型记在载体上,bag.item_type 对它恒为空(§5.8)。
func _bound_type() -> String:
	if not is_instance_valid(_bag):
		return ""
	if not _bag.item_type.is_empty():
		return _bag.item_type
	var carrier: Object = _bag.peek_state()
	if is_instance_valid(carrier):
		var carrier_type: Variant = carrier.get(&"type")
		if carrier_type is String:
			return str(carrier_type)
	return ""
