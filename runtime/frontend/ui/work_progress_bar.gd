class_name WorkProgressBar
extends HeadBar

# 工作量条:值 = 建筑当前配方的工作进度([0,1],后端由 Workshop._apply_workload
# 的 work_accum/workload_per_unit 结算并经 progress_changed 广播)。
# 复用 HeadBar 的 billboard 定位、头顶高度测量与显隐;这里只提供数据源。
#
# 放入 HeadBarGroup(竖排组)时,组负责整体定位,自身需 allow_auto_position=false;
# 数据源变化时由宿主 actor configure() 并保证 _value() 能取到数据。
#
# 工具加成闪光:配方经 tool_bonuses 声明工具时,持对工具的工人注入量被放大,放大倍率由后端
# Workshop.work_efficiency 发布(§5.4 可观察属性)。本条只读该值并归一化为闪光强度
# —— 不重算配方加成(§1 前后端分离):基准 1.0 以上才有闪光,2.0 满档,更大加成饱和。
# 闪光叠层是本条的子 ColorRect(加法混合,见 work_sparkle.gdshader),随填充区逐帧改尺寸。

const COLOR_WORK: Color = Color(0.95, 0.78, 0.25, 0.95)
const SPARKLE_SHADER: Shader = preload("res://runtime/frontend/ui/work_sparkle.gdshader")

var building: Building = null

var _sparkle: ColorRect = null
var _sparkle_material: ShaderMaterial = null

func _ready():
	# 覆盖了父类 _ready,须先调 super 让父类完成 show_percentage/样式初始化;
	# custom_minimum_size 与 allow_auto_position 由 HeadBarGroup._ready 统一设置。
	super()
	_ensure_sparkle()

func configure(in_building: Building):
	building = in_building
	# 复用池重绑时先把闪光复位:否则上个建筑若正被持械工人驱动,本条会在新建筑上
	# 残留一帧旧加成(防补播,同 §5.7 的 Actor 重绑约定)。
	_set_sparkle(0.0, 0.0)
	if building:
		set_fill_color(COLOR_WORK)
	else:
		hide()

# HeadBar 每帧(值可见时)回调:把后端发布的倍率转成闪光强度,并同步叠层几何。
func _update_visual(in_value: float):
	# 非 Workshop 无 work_efficiency 语义(与 _value() 的守卫一致);null 也在此归零。
	if building is not Workshop:
		_set_sparkle(0.0, 0.0)
		return
	var workshop: Workshop = building
	# 只有"高于基准的加成"才闪光:空手惩罚 0.1、无工具配方 1.0、无人值守 1.0 都归零。
	_set_sparkle(clampf(workshop.work_efficiency - 1.0, 0.0, 1.0), in_value)

func _value() -> float:
	# 仅 Workshop 类建筑有"配方工作进度"语义;非 Workshop 隐藏。
	if not building or building is not Workshop:
		return -1.0
	return building.progress

# 惰性建一次并复用(每建筑一条,不能每帧 new);ShaderMaterial 也复用,只改 uniform。
func _ensure_sparkle():
	if _sparkle:
		return
	_sparkle_material = ShaderMaterial.new()
	_sparkle_material.shader = SPARKLE_SHADER
	_sparkle = ColorRect.new()
	_sparkle.name = "sparkle"
	_sparkle.material = _sparkle_material
	# 纯展示:不得吞掉世界触摸/点击(与 HeadBar 同约定)。
	_sparkle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sparkle.hide()
	add_child(_sparkle)

# 刷新闪光:强度 <= 0 直接隐藏(零绘制开销);否则叠层严格覆盖填充区
# —— 宽度 = 条宽 × 当前进度,高度 = 条高,绝不超出填充(圆角由 shader 遮罩)。
func _set_sparkle(in_intensity: float, in_fill: float):
	if _sparkle == null:
		_ensure_sparkle()
	if in_intensity <= 0.0 or in_fill <= 0.0:
		_sparkle.hide()
		return
	_sparkle.position = Vector2.ZERO
	_sparkle.size = Vector2(size.x * clampf(in_fill, 0.0, 1.0), size.y)
	_sparkle_material.set_shader_parameter(&"intensity", in_intensity)
	_sparkle_material.set_shader_parameter(&"overlay_size", _sparkle.size)
	_sparkle.show()
