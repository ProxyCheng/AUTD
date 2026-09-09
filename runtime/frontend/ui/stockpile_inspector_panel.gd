class_name StockpileInspectorPanel
extends BuildingInspectorPanel

# 料堆检视面板:显示料堆当前存放的物品类型 + 库存/容量,并提供删除按钮。
# 料堆是独立 Building 子类(非 Workshop),无配方,故面板不继承 WorkshopPanel;
# 只展示其可观察属性(content_type / stored_count / capacity),随 backend 信号回流刷新。
#
# 布局约定(与 .tscn 节点对应):
#   Title          Label      标题(Stockpile)
#   CloseButton    Button     关闭钮
#   TypeLabel      Label      当前存放物品类型
#   StockBar       ProgressBar 库存占比(stored_count/capacity)
#   StockLabel     Label      库存文字 "x / y"
#   DeleteButton   Button     删除(继承基类)

var _type_label: Label = null
var _stock_bar: ProgressBar = null
var _stock_label: Label = null

func make_title(_in_building: Building) -> String:
	return "Stockpile"

func _ready():
	super()
	_type_label = get_node_or_null("TypeLabel") as Label
	_stock_bar = get_node_or_null("StockBar") as ProgressBar
	_stock_label = get_node_or_null("StockLabel") as Label

func _connect_signals():
	if building:
		building.content_type_changed.connect(_refresh)
		building.stored_count_changed.connect(_refresh)

func _disconnect_signals():
	if building:
		building.content_type_changed.disconnect(_refresh)
		building.stored_count_changed.disconnect(_refresh)

func _refresh():
	if not building:
		return
	if _type_label:
		_type_label.text = building.content_type
	if _stock_bar:
		var cap: int = building.capacity
		var stock: int = building.stored_count
		_stock_bar.max_value = maxi(cap, 1)
		_stock_bar.value = clampf(float(stock) / float(maxi(cap, 1)), 0.0, 1.0) * _stock_bar.max_value
	if _stock_label:
		_stock_label.text = "%d / %d" % [building.stored_count, building.capacity]
