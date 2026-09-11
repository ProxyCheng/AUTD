@tool
class_name ItemStack
extends Node3D

# 通用"物品堆叠"表现组件:在挂载点原点上,把若干同类型小道具按
# "平放、同向、逐横排(层)摞垛"的方式整齐摆放成一垛,供业务层(建筑模型/
# 实体 actor)按库存/携带量驱动显示。
#
# 用途:料堆盘内内容物、工人头顶携带物、弩炮甲板备箭垛……三者共用同一套
# 测量→摞垛→按数量显隐逻辑。哑表现:只吃绑定的 Bag(item_type/count)与几何配置,
# 不接触 backend 玩法逻辑(BuildingActor/EntityActor 把 Bag 转发进来)。
#
# 几何约定:垛"底面(y=0)"贴合挂载点原点所在水平面,整体水平居中于原点,
# 道具本地长轴沿挂载点 +Z 同向。挂载点自身的 rotation 决定整垛朝向
# (如挂 %cog_top 下,垛随炮塔水平转向)。道具保持原始尺寸,**整垛大小由挂载节点
# Transform 的 Scale 控制**(期望长轴 = 原始长轴 × 该 scale;原始长轴见 long_axis())。
#
# 布局:道具横躺(长轴沿 +Z),按"每排并排根数 × 层数"摞满 capacity 上限,
# 同一排内道具沿挂载点 +X 并排,相邻层沿 +Y 逐层上摞,排与层留微缝防 z-fight。

# item_type → 道具模型场景路径(推导自类型键,路径约定见 AGENTS §5.2/§8)。
# 未在表中的类型视为无模型,不显示内容。
const ITEM_MODEL_SCENES: Dictionary = {
	"arrow": "res://runtime/frontend/models/entities/arrow/arrow.tscn",
	"log": "res://runtime/frontend/models/entities/log/log.tscn",
	"stone": "res://runtime/frontend/models/entities/stone/stone.tscn",
}

# —— 几何配置(业务层按需覆盖;默认值面向"箭垛"常见形态) ——
# 编辑器里改这些值会即时重建垛(仅 @tool 下)。

enum CountMode { Raw, Fill }

# 显示数量映射:Raw=按 bag.count(可扣 count_offset);Fill=按 bag.count/bag.max_count 比例铺满几何容量。
@export var count_mode: CountMode = CountMode.Raw
# Raw 模式下从 bag.count 扣掉的件数(如弩炮"在弦上的一支"由别处显示)。
@export var count_offset: int = 0

# 绑定的 backend 展示仓;bind() 后本垛跟随其 item_type/count 变化。
var bag: Bag = null

# 物品种类(可在场景里预置;空则不显示内容,待 _set_item_type)
@export var item_type: String = "":
	set(in_type):
		item_type = in_type
		if in_type != _item_type:
			_set_item_type(in_type)

# 满堆可见道具上限 = per_row × layer_count(表现预算;更大容量时每支代表一批)
@export var per_row: int = 3:
	set(in_value):
		per_row = in_value
		_rebuild()
@export var layer_count: int = 3:
	set(in_value):
		layer_count = in_value
		_rebuild()
# 同一排内相邻道具横向间距系数(相对道具宽度)
@export var row_spacing: float = 1.05:
	set(in_value):
		row_spacing = in_value
		_rebuild()
# 相邻两层垂直间距系数(相对道具缩放后厚度),留微缝防 z-fight
@export var layer_spacing: float = 1.2:
	set(in_value):
		layer_spacing = in_value
		_rebuild()

var _props: Array[Node3D] = []
var _content: Node3D = null
var _item_type: String = ""
# 按绑定 Bag 折算出的可见道具数(0..capacity)
var _shown_count: int = 0
# 道具原始长轴(未缩放);业务层可用 long_axis() 把期望长度换算成挂载节点 scale
var _long_axis: float = 1.0
# 编辑器"选中即预览铺满"状态与其半透材质
var _preview_full: bool = false
var _ghost_mat: StandardMaterial3D = null

func _ready():
	_content = Node3D.new()
	_content.name = "Items"
	add_child(_content)
	# 注意:导出属性 item_type 在场景实例化时(未进树)已把 _item_type 置好,
	# 这里必须直接 _rebuild 而不是 _set_item_type(会被同值 guard 挡掉)。
	_rebuild()

# 编辑器:选中本节点时预览"铺满容量"的半透内容物;取消选中即还原。
func _process(_delta: float):
	if not Engine.is_editor_hint():
		return
	_set_preview_full(_is_selected_in_editor())

func _is_selected_in_editor() -> bool:
	var sel := EditorInterface.get_selection()
	if sel == null:
		return false
	for n: Node in sel.get_selected_nodes():
		if n == self:
			return true
	return false

func _set_preview_full(in_on: bool):
	if _preview_full == in_on:
		return
	_preview_full = in_on
	_apply_visibility()
	_apply_preview_material()

# 预览时把每个道具换成半透"幽灵"材质(替换 material_override);关闭时清空还原。
func _apply_preview_material():
	for p: Node3D in _props:
		if is_instance_valid(p):
			_apply_prop_material(p, _preview_full)

func _apply_prop_material(in_node: Node, in_ghost: bool):
	for child in in_node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = _preview_material() if in_ghost else null
		_apply_prop_material(child, in_ghost)

func _preview_material() -> StandardMaterial3D:
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.albedo_color = Color(0.35, 0.85, 1.0, 0.35)
		_ghost_mat.emission_enabled = true
		_ghost_mat.emission = Color(0.2, 0.6, 1.0)
		_ghost_mat.emission_energy_multiplier = 0.6
	return _ghost_mat

# 满堆可见上限
func capacity() -> int:
	return per_row * layer_count

# 道具原始长轴(本地、未缩放)。业务层可据此把"期望长度"换算成挂载节点的 scale:
#   scale = 期望长度 / long_axis()
func long_axis() -> float:
	return _long_axis

# 设置物品种类:重建对应道具池(未进树则等 _ready 后由 build 入口确保)。
func _set_item_type(in_type: String):
	if in_type == _item_type:
		return
	_item_type = in_type
	_rebuild()

# 依据当前 _item_type 重建道具池(清空→按类型重建)。未进树时跳过。
func _rebuild():
	if not is_inside_tree():
		return
	_clear_props()
	if ITEM_MODEL_SCENES.has(_item_type):
		_build_props(ITEM_MODEL_SCENES[_item_type])
	_apply_preview_material()

# 当前可见的道具(供业务层取"垛顶那支"等);不含内部容器/Gizmo。
func _visible_props() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for p: Node3D in _props:
		if is_instance_valid(p) and p.visible:
			out.append(p)
	return out

# 当前可见道具数(供业务层取末位索引:visible_count() - 1)。
func visible_count() -> int:
	var n: int = 0
	for p: Node3D in _props:
		if is_instance_valid(p) and p.visible:
			n += 1
	return n

# 取第 in_index 个可见道具的世界空间 TRS(position/rotation/scale 全量),
# 供业务层做"从垛里这支 → 目标姿态"的整段插值动画。顺序 = 摞垛顺序(0 起,末位为最上层那支)。
# 越界 / 未建 / 不可见 → 返回 null(表示垛里没有这一支)。
# 约定:一律返回世界空间;调用方如需其它空间,自行用目标节点 global 的逆变换换算。
func get_prop_transform(in_index: int) -> Variant:
	if in_index < 0:
		return null
	var vis := _visible_props()
	if in_index >= vis.size():
		return null
	return vis[in_index].global_transform

# 绑定 backend Bag:断开旧仓 → 连接新仓的 count/item_type 信号 → 全量刷新一次。
# 传 null 解除绑定(只清空可见数量,保留场景预设 item_type 供编辑器预览)。
func bind(in_bag: Bag):
	_unbind()
	bag = in_bag
	if not is_instance_valid(bag):
		bag = null
		_apply_display_count()
		return
	if not bag.count_changed.is_connected(_on_bag_count_changed):
		bag.count_changed.connect(_on_bag_count_changed)
	if bag.has_signal(&"item_type_changed") and not bag.item_type_changed.is_connected(_on_bag_item_type_changed):
		bag.item_type_changed.connect(_on_bag_item_type_changed)
	_refresh()

func _unbind():
	if is_instance_valid(bag):
		if bag.count_changed.is_connected(_on_bag_count_changed):
			bag.count_changed.disconnect(_on_bag_count_changed)
		if bag.has_signal(&"item_type_changed") and bag.item_type_changed.is_connected(_on_bag_item_type_changed):
			bag.item_type_changed.disconnect(_on_bag_item_type_changed)
	bag = null

func _refresh():
	if is_instance_valid(bag):
		_set_item_type(bag.item_type)
	_apply_display_count()

func _on_bag_count_changed():
	_apply_display_count()

func _on_bag_item_type_changed():
	if is_instance_valid(bag):
		_set_item_type(bag.item_type)

# 按 count_mode/count_offset 把 bag.count 折算为可见道具数并应用显隐。
func _apply_display_count():
	_shown_count = _display_count()
	if _props.is_empty():
		return
	_apply_visibility()

func _display_count() -> int:
	if not is_instance_valid(bag):
		return 0
	var n: int = bag.count
	if count_mode == CountMode.Fill:
		if n <= 0 or bag.max_count <= 0:
			return 0
		return clampi(maxi(1, roundi(float(n) / float(bag.max_count) * float(capacity()))), 0, capacity())
	return clampi(n - count_offset, 0, capacity())

# 可见道具数 = 业务层要求(_shown_count);编辑器选中预览时强制铺满。
func _apply_visibility():
	var visible_count: int = capacity() if _preview_full else _shown_count
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
	_long_axis = box.size.z
	# 道具保持原生尺寸;整垛大小交给挂载节点 Transform 的 Scale 控制。
	var width: float = box.size.x
	var thickness: float = box.size.y
	var bottom_offset: float = box.position.y
	# 网格可能不沿长轴居中(arrow 本地 z 从 0 起伸),按中心平移让垛居中于原点
	var center_z: float = box.position.z + box.size.z * 0.5
	var row_x := width * row_spacing
	var layer_y := thickness * layer_spacing
	for i in range(capacity()):
		var row: int = i % per_row
		var layer: int = i / per_row
		var prop: Node3D = prop_scene.instantiate()
		prop.rotation = Vector3.ZERO
		prop.scale = Vector3.ONE
		var x: float = (float(row) - float(per_row - 1) * 0.5) * row_x
		var y: float = -bottom_offset + float(layer) * layer_y
		prop.position = Vector3(x, y, -center_z)
		_content.add_child(prop)
		_props.append(prop)
	# build 完成后应用可见性(count 可能先于 build 设置,已记在 _shown_count)
	_apply_visibility()

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
