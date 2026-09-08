class_name ItemStack
extends Node3D

# 通用"物品堆叠"表现组件:在挂载点原点上,把若干同类型小道具按
# "平放、同向、逐横排(层)摞垛"的方式整齐摆放成一垛,供业务层(建筑模型/
# 实体 actor)按库存/携带量驱动显示。
#
# 用途:料堆盘内内容物、工人头顶携带物、弩炮甲板备箭垛……三者共用同一套
# 测量→缩放→摞垛→按数量显隐逻辑。哑表现:只吃 item_type/count 与几何配置,
# 不接触 backend 玩法逻辑(BuildingActor/EntityActor 已把 backend 信号转发进来)。
#
# 几何约定:垛"底面(y=0)"贴合挂载点原点所在水平面,整体水平居中于原点,
# 道具本地长轴沿挂载点 +Z 同向。挂载点自身的 rotation 决定整垛朝向
# (如挂 %cog_top 下,垛随炮塔水平转向)。所有尺寸以挂载点本地坐标为准。
#
# 布局:道具横躺(长轴沿 +Z),按"每排并排根数 × 层数"摞满 capacity 上限,
# 同一排内道具沿挂载点 +X 并排,相邻层沿 +Y 逐层上摞,排与层留微缝防 z-fight。

# item_type → 道具模型场景路径(推导自类型键,路径约定见 AGENTS §5.2/§8)。
# 未在表中的类型视为无模型,不显示内容。
const ITEM_MODEL_SCENES: Dictionary = {
	"arrow": "res://runtime/frontend/models/entities/arrow/arrow.tscn",
}

# —— 几何配置(业务层按需覆盖;默认值面向"箭垛"常见形态) ——

# 满堆可见道具上限 = per_row × layer_count(表现预算;更大容量时每支代表一批)
@export var per_row: int = 3
@export var layer_count: int = 3
# 道具横躺后的目标长轴长度(沿挂载点 +Z)。按道具原始 AABB 长轴等比缩放。
@export var target_length: float = 0.5
# 同一排内相邻道具横向间距系数(相对道具缩放后宽度)
@export var row_spacing: float = 1.05
# 相邻两层垂直间距系数(相对道具缩放后厚度),留微缝防 z-fight
@export var layer_spacing: float = 1.2

var _props: Array[Node3D] = []
var _content: Node3D = null
var _item_type: String = ""
# count 可能早于 build 到达(信号先到、build 后到),缓存待 build 后应用
var _pending_count: int = 0

func _ready():
	_content = Node3D.new()
	_content.name = "Items"
	add_child(_content)

# 满堆可见上限
func capacity() -> int:
	return per_row * layer_count

# 设置物品种类:重建对应道具池(未进树则等 _ready 后由 build 入口确保)。
# change 时先清空旧池,重建时依据当前 item_type。
func set_item_type(in_type: String):
	if in_type == _item_type:
		return
	_item_type = in_type
	_clear_props()
	if not is_inside_tree():
		return
	if not ITEM_MODEL_SCENES.has(in_type):
		return
	_build_props(ITEM_MODEL_SCENES[in_type])

# 业务层转发库存/携带量变化:按 count 决定可见道具数(0..capacity)。
# 调用方负责把"在弦上的一支"这类语义扣掉后再传入。
# props 未建(信号先于 build)时缓存,待 _build_props 末尾统一应用。
func set_count(in_count: int):
	var visible_count: int = clampi(in_count, 0, capacity())
	if _props.is_empty():
		_pending_count = visible_count
		return
	for i in range(_props.size()):
		_props[i].visible = i < visible_count

# 废弃/离树时清理,复用池不残留
func _clear_props():
	for prop in _props:
		if is_instance_valid(prop):
			prop.queue_free()
	_props.clear()

# 在挂载点原点把道具按"每排并排、逐层上摞"排成整齐垛,全部同一朝向。
# 假定道具场景长轴沿本地 +Z;测量得本地 AABB 后统一缩放至 TARGET_LENGTH,
# 再按宽度排横向间距、按厚度定层高,整垛底边贴合木点 y=0。
func _build_props(in_scene_path: String):
	var prop_scene: PackedScene = load(in_scene_path)
	if not prop_scene:
		return
	var probe: Node3D = prop_scene.instantiate()
	var box := _measure_local_box(probe)
	probe.free()
	if box.size.z <= 0.0:
		return
	var scale_factor: float = target_length / box.size.z
	var width: float = box.size.x * scale_factor
	var thickness: float = box.size.y * scale_factor
	var bottom_offset: float = box.position.y * scale_factor
	# 网格可能不沿长轴居中(arrow 本地 z 从 0 起伸),按中心平移让垛居中于原点
	var center_z: float = (box.position.z + box.size.z * 0.5) * scale_factor
	var row_x := width * row_spacing
	var layer_y := thickness * layer_spacing
	for i in range(capacity()):
		var row: int = i % per_row
		var layer: int = i / per_row
		var prop: Node3D = prop_scene.instantiate()
		# 先设 rotation(basis)再设 scale——Node3D 的 scale 由 basis 分解,反向会被覆盖
		prop.rotation = Vector3.ZERO
		prop.scale = Vector3.ONE * scale_factor
		var x: float = (float(row) - float(per_row - 1) * 0.5) * row_x
		var y: float = -bottom_offset + float(layer) * layer_y
		prop.position = Vector3(x, y, -center_z)
		_content.add_child(prop)
		_props.append(prop)
	# build 完成后应用 count(count 可能先于 build 设置,已缓存在 _pending_count)
	if _props.size() > 0:
		set_count(_pending_count)

# 离树探针:返回道具本地空间合并 AABB(position=min, size)。用节点链式变换
# 求本地 AABB,不依赖 global_transform,规避实例化当帧传播未生效的时序问题。
func _measure_local_box(in_probe: Node3D) -> AABB:
	var min_p := Vector3.INF
	var max_p := -Vector3.INF
	for visual: VisualInstance3D in _collect_visuals(in_probe):
		var local_to_probe := _chain_to(visual, in_probe)
		var aabb: AABB = visual.get_aabb()
		var corners := [
			aabb.position,
			aabb.position + Vector3(aabb.size.x, 0, 0),
			aabb.position + Vector3(0, aabb.size.y, 0),
			aabb.position + Vector3(0, 0, aabb.size.z),
			aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
			aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
			aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
			aabb.end,
		]
		for corner in corners:
			var p: Vector3 = local_to_probe * corner
			min_p = min_p.min(p)
			max_p = max_p.max(p)
	return AABB(min_p, max_p - min_p)

# 逐级父链变换:返回把 in_node 本地坐标变换到 in_probe 本地坐标的 Transform3D
func _chain_to(in_node: Node3D, in_probe: Node3D) -> Transform3D:
	var acc := Transform3D.IDENTITY
	var current: Node3D = in_node
	while current != in_probe:
		acc = current.transform * acc
		current = current.get_parent() as Node3D
		if not current:
			break
	return acc

func _collect_visuals(in_node: Node) -> Array[VisualInstance3D]:
	var visuals: Array[VisualInstance3D] = []
	for child in in_node.get_children():
		if child is VisualInstance3D:
			visuals.append(child as VisualInstance3D)
		visuals.append_array(_collect_visuals(child))
	return visuals
