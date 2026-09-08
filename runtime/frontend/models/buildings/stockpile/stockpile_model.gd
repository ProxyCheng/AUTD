class_name StockpileModel
extends Node3D

# 料堆(空底盘)的内容物显示:content_type 决定用哪个物品模型,stored_count/capacity
# 决定同时可见的道具数——存货越多,盘内同向摞起的箭垛层数越多,呈现堆叠程度。
# 哑表现脚本:只吃 BuildingActor 转发的字符串/数值,不接触 backend 逻辑。
#
# 几何测量说明:道具尺寸在其 node.transform 链上即可求(无需进树/等帧传播),
# 故测量在离树探针上做本地空间 AABB 计算,避免 add_child 后当帧
# global_transform 未更新导致的失真。

# item_type → 物品模型场景路径(推导自类型键,路径约定见 AGENTS §5.2/§8)。
# 暂只 arrow 有模型;其余类型无模型时内容物不显示。
const ITEM_MODEL_SCENES: Dictionary = {
	"arrow": "res://runtime/frontend/models/entities/arrow/arrow.tscn",
}

# 满堆时可见道具数上限(表现预算;容量更大时每根道具代表"一束/一批",不逐根计数)
const MAX_PROPS: int = 12
# 道具横躺后的目标长度(箭杆长轴)。料堆内腔地板可用直径实测约 0.68(内壁半径~0.34),
# 长轴沿垛宽方向摆放时须留边距,0.5 为安全值。
const PROP_LENGTH: float = 0.5
# 盘底内底面离模型原点的世界 y(blend 底盘内腔底)
const FLOOR_Y: float = 0.03
# 摞垛:每排并排根数 × 层数 = MAX_PROPS。所有道具同一朝向(模型长轴沿自身 +Z)。
const PROPS_PER_ROW: int = 4
const ROW_COUNT: int = 3
# 同一排内相邻道具的横向间距系数(相对道具宽度)
const ROW_SPACING: float = 1.05
# 相邻两层垂直间距系数(相对道具厚度),留微缝防 z-fight
const LAYER_SPACING: float = 1.2

var _item_type: String = ""
var _content: Node3D = null
var _props: Array[Node3D] = []

func _ready():
	_content = Node3D.new()
	_content.name = "Items"
	add_child(_content)

# BuildingActor 转发 content_type 变化:重建对应物品模型的道具池(未进树则缓存到下次)
func set_content_type(in_type: String):
	if in_type == _item_type:
		return
	_item_type = in_type
	_clear_props()
	if not is_inside_tree():
		return
	if not ITEM_MODEL_SCENES.has(in_type):
		return
	_build_props(ITEM_MODEL_SCENES[in_type])

# BuildingActor 转发存量变化:按 count/capacity 决定可见道具数
func set_stored_count(in_count: int, in_capacity: int):
	var visible_count: int = 0
	if in_count > 0 and in_capacity > 0:
		var fill: float = clampf(float(in_count) / float(in_capacity), 0.0, 1.0)
		visible_count = maxi(1, roundi(fill * MAX_PROPS))
	for i in range(_props.size()):
		_props[i].visible = i < visible_count

func _clear_props():
	for prop in _props:
		if is_instance_valid(prop):
			prop.queue_free()
	_props.clear()

# 在盘底把道具按"每排并排、逐层上摞"排成整齐垛,全部同一朝向。
# 假定道具场景长轴沿本地 +Z;测量得本地 AABB 后统一缩放至 PROP_LENGTH,
# 再按宽度排横向间距、按厚度定层高,整垛底边贴合 FLOOR_Y。
func _build_props(in_scene_path: String):
	var item_scene: PackedScene = load(in_scene_path)
	if not item_scene:
		return
	var probe: Node3D = item_scene.instantiate()
	var box := _measure_local_box(probe)
	probe.free()
	if box.size.z <= 0.0:
		return
	var scale_factor: float = PROP_LENGTH / box.size.z
	var width: float = box.size.x * scale_factor
	var thickness: float = box.size.y * scale_factor
	var bottom_offset: float = box.position.y * scale_factor
	# 网格可能不沿长轴居中(arrow 本地 z 从 0 起伸),按中心平移让垛居中于盘心
	var center_z: float = (box.position.z + box.size.z * 0.5) * scale_factor
	var row_x := width * ROW_SPACING
	var layer_y := thickness * LAYER_SPACING
	for i in range(MAX_PROPS):
		var row: int = i % PROPS_PER_ROW
		var layer: int = i / PROPS_PER_ROW
		var prop: Node3D = item_scene.instantiate()
		# 先设 rotation(basis)再设 scale——Node3D 的 scale 由 basis 分解,反向会被覆盖
		prop.rotation = Vector3.ZERO
		prop.scale = Vector3.ONE * scale_factor
		var x: float = (float(row) - float(PROPS_PER_ROW - 1) * 0.5) * row_x
		var y: float = FLOOR_Y - bottom_offset + float(layer) * layer_y
		prop.position = Vector3(x, y, -center_z)
		_content.add_child(prop)
		_props.append(prop)

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
