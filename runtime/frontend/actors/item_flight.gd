class_name ItemFlight
extends Node3D

# 一次性"物品飞行"表现:工人从建筑取/放物品时,让该件物品的模型从起点(工人头/手)
# 飞到终点(建筑的料堆;建筑没有垛时给中心 + 缩放 0,读作"到地方就消失 / 从无到有")。
#
# 两端各是一份完整的世界空间 TRS,飞行期间三样一起过渡:位置走直线并叠加倒 U 拱高,
# 朝向与缩放整段交给 Trs.lerp —— 它有"缩放为 0"端点的处理,见该类注释。
#
# 纯表现 + 自管生命周期:launch() 只造节点与道具模型,**不把它挂进场景树** ——
# 调用方 add_child 后 _ready 才开始推进,播完即 queue_free(一次性表现无复用价值,
# 同 CannonballBurst)。不用 Tween:两端姿态全是 Transform3D 输入,按归一化进度直接
# 采样最直观,也不会出现节点被回收后 Tween 仍持有引用的问题。
#
# 姿态契约:道具模型按 ItemStack 的归一化约定摆正(rotation=ZERO、scale=ONE),
# 位置/朝向/缩放全部由本节点承担 —— 这样飞行中的道具与垛里那支看起来是同一个东西。

# —— 时长参数(纯表现,可直接调) ——
# 飞行速度(米/秒):时长 = 起终点直线距离 / 本值,再夹到下面的上下限。
const SPEED: float = 6.0
# 时长下限(秒):贴脸取放(同一格内)也要走完一小段,不能瞬移。
const MIN_DURATION: float = 0.18
# 时长上限(秒):长距离搬运不拖沓,节奏一眼跟得上。
const MAX_DURATION: float = 0.9

# —— 倒 U 轨迹参数 ——
# 拱高系数:弧顶抬升 = 直线距离 × 本值(同 CannonModel.LOAD_BALL_ARC_RATIO 的几何思路)。
const ARC_RATIO: float = 0.35
# 拱高下限(米):只兜住起终点重合的退化情形;刻意取得极小,近距离不会鼓成一个包。
const ARC_MIN_HEIGHT: float = 0.05
# 拱高上限(米):长距离搬运不把弧顶抬到天上,读作"抛过去"而非"飞越"。
const ARC_MAX_HEIGHT: float = 2.5

# 起点/终点姿态(世界空间 TRS),launch 时写死,飞行期间只读。
var _from: Transform3D = Transform3D.IDENTITY
var _to: Transform3D = Transform3D.IDENTITY
# 已播时长与总时长(秒):总时长在 launch 时按距离算好并夹取。
var _elapsed: float = 0.0
var _duration: float = 0.0
# 弧顶抬升量(米):按直线距离一次算好,避免每帧重复求。
var _arc: float = 0.0

# 工厂:按 item_type 查 ItemStack 的道具场景表,造出一个**尚未入树**的飞行节点。
# 未知类型 / 场景加载失败 → 返回 null(未知类型是预期情况,调用方跳过动画即可,不报错)。
static func launch(in_type: String, in_from: Transform3D, in_to: Transform3D) -> ItemFlight:
	if in_type.is_empty() or not ItemStack.ITEM_MODEL_SCENES.has(in_type):
		return null
	var scene_path: String = ItemStack.ITEM_MODEL_SCENES[in_type]
	var prop_scene: PackedScene = load(scene_path)
	if not prop_scene:
		return null
	var prop: Node3D = prop_scene.instantiate() as Node3D
	if not prop:
		# 场景根不是 3D 节点时无法承担姿态,视同无模型
		return null
	var flight := ItemFlight.new()
	flight._from = in_from
	flight._to = in_to
	# 时长/拱高都只由直线距离推出:近处快而贴地,远处慢而抬高,但都被上下限兜住。
	var distance: float = in_from.origin.distance_to(in_to.origin)
	flight._duration = clampf(distance / SPEED, MIN_DURATION, MAX_DURATION)
	flight._arc = clampf(distance * ARC_RATIO, ARC_MIN_HEIGHT, ARC_MAX_HEIGHT)
	flight.name = "ItemFlight_%s" % in_type
	# 归一化同 ItemStack._build_props:模型只摆姿态,尺寸交给本节点 Transform 的缩放。
	# 这里不置 visible —— 垛里置 false 是为了数量显隐,飞行中这件必须可见。
	prop.rotation = Vector3.ZERO
	prop.scale = Vector3.ONE
	flight.add_child(prop)
	return flight

# 入树即启动:先把首帧姿态摆到起点,避免第一帧从原点/单位姿态闪过去。
func _ready():
	_apply(0.0)

func _process(in_delta: float):
	if _duration <= 0.0:
		# 未经 launch 的裸实例(既无时长也无模型)直接回收,避免除零
		queue_free()
		return
	# 进度夹在总时长上,故 k 恒不越过 1.0;播完立即自毁,不常驻场景树。
	_elapsed = minf(_elapsed + in_delta, _duration)
	_apply(_elapsed / _duration)
	if _elapsed >= _duration:
		queue_free()

# 按归一化进度 in_k ∈ [0,1] 采样姿态:位置走直线并叠加倒 U 拱高(不穿地面/建筑),
# 朝向与缩放整段交给 Trs.lerp。
func _apply(in_k: float):
	var pose: Transform3D = Trs.lerp(_from, _to, in_k)
	pose.origin.y += 4.0 * _arc * in_k * (1.0 - in_k)
	global_transform = pose
