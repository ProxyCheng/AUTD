class_name WorkProgressBar
extends HeadBar

# 工作量条:值 = 建筑当前配方的工作进度([0,1],后端由 Workshop._apply_workload
# 的 work_accum/workload_per_unit 结算并经 progress_changed 广播)。
# 复用 HeadBar 的 billboard 定位、头顶高度测量与显隐;这里只提供数据源。
#
# 放入 HeadBarGroup(竖排组)时,组负责整体定位,自身需 allow_auto_position=false;
# 数据源变化时由宿主 actor configure() 并保证 _value() 能取到数据。

const COLOR_WORK: Color = Color(0.95, 0.78, 0.25, 0.95)

var building: Building = null

func _ready():
	# 覆盖了父类 _ready,须先调 super 让父类完成 show_percentage/样式初始化;
	# custom_minimum_size 与 allow_auto_position 由 HeadBarGroup._ready 统一设置。
	super()

func configure(in_building: Building):
	building = in_building
	if building:
		set_fill_color(COLOR_WORK)
	else:
		hide()

func _value() -> float:
	# 仅 Workshop 类建筑有"配方工作进度"语义;非 Workshop 隐藏。
	if not building or building is not Workshop:
		return -1.0
	return building.progress
