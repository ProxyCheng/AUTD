class_name ItemFlight
extends Node3D

# 一次性"物品飞行"表现:由**一次计时搬运**(ItemTransfer)的 progress 驱动 ——
# 后端开趟当帧就扣货、到点才把货交给目标仓(见 ItemTransfer),本节点只是把这段过程
# 画成"物品从起点飞到终点"。
#
# 故本节点**不自带计时器**:进度是后端的事实,表现跟着它走(§5.4 的 progress 契约:
# 数据层只出归一化进度,到动画时间轴的换算在表现层)。后端把整段拉长/缩短,飞行自动跟着变。
#
# 两端各是一份完整的世界空间 TRS,三样一起过渡:位置走直线并叠加倒 U 拱高,朝向与缩放
# 整段交给 Trs.lerp(它有"缩放为 0"端点的处理,见该类注释)。
#
# 姿态契约:道具模型按 ItemStack 的归一化约定摆正(rotation=ZERO、scale=ONE),
# 位置/朝向/缩放全部由本节点承担 —— 这样飞行中的道具与垛里那支看起来是同一个东西。

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
# 弧顶抬升量(米):按直线距离一次算好,避免每帧重复求。
var _arc: float = 0.0
# 驱动本表现的搬运(由 follow 绑定);终态即自毁。
var _transfer: ItemTransfer = null

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
	flight._arc = clampf(in_from.origin.distance_to(in_to.origin) * ARC_RATIO,
			ARC_MIN_HEIGHT, ARC_MAX_HEIGHT)
	flight.name = "ItemFlight_%s" % in_type
	# 归一化同 ItemStack._build_props:模型只摆姿态,尺寸交给本节点 Transform 的缩放。
	# 这里不置 visible —— 垛里置 false 是为了数量显隐,飞行中这件必须可见。
	prop.rotation = Vector3.ZERO
	prop.scale = Vector3.ONE
	flight.add_child(prop)
	return flight

# 绑到驱动本表现的搬运:先按当前进度摆一次姿态(别等下一帧才从原点闪过来),
# 之后跟着 progress 走,搬运一进终态就自毁。
# 调用方须先把本节点 add_child 进树(挂 RoomActor —— 这样工人 actor 被回收也不影响它飞完)。
func follow(in_transfer: ItemTransfer):
	_transfer = in_transfer
	in_transfer.progress_changed.connect(_on_progress_changed)
	in_transfer.finished.connect(_on_transfer_finished)
	_apply(in_transfer.progress)

func _on_progress_changed():
	if is_instance_valid(_transfer):
		_apply(_transfer.progress)

func _on_transfer_finished(_in_state: int):
	queue_free()

# 按归一化进度 in_k ∈ [0,1] 采样姿态:位置走直线并叠加倒 U 拱高(不穿地面/建筑),
# 朝向与缩放整段交给 Trs.lerp。
func _apply(in_k: float):
	var pose: Transform3D = Trs.lerp(_from, _to, in_k)
	pose.origin.y += 4.0 * _arc * in_k * (1.0 - in_k)
	global_transform = pose
