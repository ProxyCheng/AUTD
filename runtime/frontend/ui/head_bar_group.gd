class_name HeadBarGroup
extends VBoxContainer

# 头顶悬浮条竖排组:把 1~N 条 HeadBar(如工作量条/未来多进度)竖向堆叠在模型头顶,
# 由本组统一做 billboard 投影定位(VBoxContainer 自动竖排子条,子条自身不做定位)。
#
# 用法:host actor 在几何就绪后调 setup(host, model) 挂锚点并测量模型头顶高度;
# 子条(HeadBar 子类)必须设 allow_auto_position = false,由本组统一定位;
# 任一字条本帧应显示(其 _value() >= 0)则整组显示,否则隐藏。

# 条组底边相对头顶投影点的上移间隙(像素),与单条 HeadBar.BAR_GAP_PX 保持一致
const BAR_GAP_PX: float = 10.0

var host: Node3D = null        # 承载组的世界锚点(actor 根)
var model: Node3D = null       # 要测量头顶高度的模型(host 的子节点)
var model_height: float = 0.0  # 模型头顶高度(相对 host 本地 y),由 AABB 结算

func setup(in_host: Node3D, in_model: Node3D):
	host = in_host
	model = in_model
	_refresh_model_height()

func _ready():
	# 条组是纯展示:不得吞掉世界触摸/点击(触屏上会挡住放置/选中)。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 本组统一做 billboard 定位,子条自身不再定位(VBoxContainer 竖排会接管位置);
	# 容器按排版压缩子条,须给最小高度,否则会被压到几乎不可见。
	for child in get_children():
		if child is HeadBar:
			child.allow_auto_position = false
			child.custom_minimum_size = Vector2(0, 5)

# 数据源变化(bind 新对象)时由宿主 actor 调用:把数据喂给全部子条
# (各条 configure 签名由具体子类定义,如 WorkProgressBar.configure(building))。
func bind_source(in_data):
	for child in get_children():
		if child is HeadBar and child.has_method(&"configure"):
			child.configure(in_data)

func _process(_in_delta: float):
	if not host or model_height <= 0.0:
		hide()
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		hide()
		return
	# 任一子条本帧应显示?(_value() >= 0 表示该条有数据要展示)
	if not _any_bar_value():
		hide()
		return
	var screen := HeadBar.project_screen(host, model_height, camera)
	if screen.x < 0.0:
		hide()
		return
	# 组整体居中放到头顶锚点上方;子条间距由 VBoxContainer 的 separation 控制
	position = Vector2(screen.x - size.x * 0.5, screen.y - size.y - BAR_GAP_PX)
	show()

# 遍历全部子条(HeadBar 子类),只要有一条 _value() >= 0 即认为整组应显示。
func _any_bar_value() -> bool:
	for child in get_children():
		if child is HeadBar and child._value() >= 0.0:
			return true
	return false

# 模型头顶高度:AABB 结算(复用 HeadBar 静态工具;in_probe 用本组,与 actor 本地空间一致)。
func _refresh_model_height():
	model_height = 0.0
	if not model:
		return
	var box := HeadBar.measure_box(model, host if host else model)
	if box.size == Vector3.ZERO:
		return
	model_height = box.end.y
