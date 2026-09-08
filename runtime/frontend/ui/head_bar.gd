class_name HeadBar
extends ProgressBar

# 头顶悬浮条通用基类(血条/容量条等):自绘样式 + billboard 投影定位 + 按需显隐,
# 并把"求模型头顶高度"的 AABB 测量提为静态方法供宿主 actor 共用。
#
# 子类只覆写两处差异:
#   _value()           返回 [0,1] 的显示占比;返回负值表示本帧不显示。
#   _update_visual(v)  每帧可选外观刷新(如血条按阵营染色);默认空。
# 子类还需:在几何就绪后调 setup(host, model) 挂锚点并测量高度;
# 数据源变化时(如 bind 新对象)由子类配置各自的 configure() 并保证 _value() 能取到数据。
#
# 样式在 _ready 自建并复制 fill StyleBoxFlat,避免污染共享 SubResource。

# 条底边相对头顶投影点的上移间隙(像素)
const BAR_GAP_PX: float = 10.0
# 头顶锚点相对模型顶面再往上的世界高度间隙(米)
const TOP_GAP_WORLD: float = 0.1

var host: Node3D = null        # 承载条的世界锚点(actor 根);其 global_position+up 定基准
var model: Node3D = null       # 要测量头顶高度的模型(host 的子节点)
var model_height: float = 0.0  # 模型头顶高度(相对 host 本地 y),由 AABB 结算

var _fill_style: StyleBoxFlat = null

func setup(in_host: Node3D, in_model: Node3D):
	host = in_host
	model = in_model
	_refresh_model_height()

# 子类覆写:返回 [0,1] 显示占比;负值 = 本帧隐藏。
func _value() -> float:
	return -1.0

# 子类可选覆写:每帧外观刷新(值变化时调用)。
func _update_visual(_in_value: float):
	pass

func _ready():
	show_percentage = false
	_ensure_styles()

func _process(_in_delta: float):
	var value := _value()
	if value < 0.0 or model_height <= 0.0 or not host:
		hide()
		return
	_update_visual(value)
	max_value = 100.0
	self.value = clampf(value, 0.0, 1.0) * 100.0
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	# 沿相机 up 方向抬升模型顶上一基准点,投影后把条居中放到其上方
	var anchor := host.global_position + camera.transform.basis.y * (model_height + TOP_GAP_WORLD)
	if camera.is_position_behind(anchor):
		hide()
		return
	var screen := camera.unproject_position(anchor)
	position = Vector2(screen.x - size.x * 0.5, screen.y - size.y - BAR_GAP_PX)
	show()

# —— 样式(自建 bg/fill,fill 复制一份避免跨实例污染颜色) ——

func _ensure_styles():
	if _fill_style:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	add_theme_stylebox_override("background", bg)
	_fill_style = StyleBoxFlat.new()
	_fill_style.set_corner_radius_all(3)
	add_theme_stylebox_override("fill", _fill_style)

func set_fill_color(in_color: Color):
	if _fill_style == null:
		_ensure_styles()
	_fill_style.bg_color = in_color

# —— 模型头顶高度:AABB 结算(静态工具供宿主共用) ——

func _refresh_model_height():
	model_height = 0.0
	if not model:
		return
	var box := measure_box(model, self_host())
	if box.size == Vector3.ZERO:
		return
	model_height = box.end.y

# 求框用宿主作探针(与 entity_actor 本地空间约定一致);无宿主时退回模型自身。
func self_host() -> Node3D:
	return host if host else model

# 求 in_node 子树在 in_probe 本地坐标系的合并 AABB(逐级父链变换累乘,含镜像/非等比缩放)。
static func measure_box(in_node: Node3D, in_probe: Node3D) -> AABB:
	var min_p := Vector3.INF
	var max_p := -Vector3.INF
	for visual: VisualInstance3D in collect_visual_instances(in_node):
		var to_probe := chain_to(visual, in_probe)
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
			var p: Vector3 = to_probe * corner
			min_p = min_p.min(p)
			max_p = max_p.max(p)
	if min_p == Vector3.INF:
		return AABB()
	return AABB(min_p, max_p - min_p)

# 把 in_node 本地坐标变换到 in_probe 本地坐标的 Transform3D(逐级父链累乘)。
static func chain_to(in_node: Node3D, in_probe: Node3D) -> Transform3D:
	var acc := Transform3D.IDENTITY
	var current: Node3D = in_node
	while current != in_probe:
		acc = current.transform * acc
		current = current.get_parent() as Node3D
		if not current:
			break
	return acc

static func collect_visual_instances(in_node: Node) -> Array[VisualInstance3D]:
	var visuals: Array[VisualInstance3D] = []
	for child in in_node.get_children():
		if child is VisualInstance3D:
			visuals.append(child as VisualInstance3D)
		visuals.append_array(collect_visual_instances(child))
	return visuals
