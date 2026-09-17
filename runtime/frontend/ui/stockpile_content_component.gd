class_name StockpileContentComponent
extends InspectorComponent

# 料堆内容组件:服务 Stockpile —— 显示当前存放物品类型 + 库存/容量。
# 料堆是独立 Building 子类(非 Workshop),无配方;本组件只读其可观察属性
# (content_type / stored_count / capacity),随 backend 信号回流刷新(§5.4)。

var _type_label: Label = null
var _stock_bar: ProgressBar = null
var _stock_label: Label = null

func supports(in_target: Object) -> bool:
	return in_target is Stockpile

func _ready():
	_type_label = get_node_or_null("%TypeLabel") as Label
	_stock_bar = get_node_or_null("%StockBar") as ProgressBar
	_stock_label = get_node_or_null("%StockLabel") as Label
	# 库存条 = 容量占用率,与建筑头顶容量条(BuildingCapacityBar)同一语义、同一配色
	if _stock_bar:
		apply_bar_fill(_stock_bar, BuildingCapacityBar.COLOR_CAPACITY)
	# bind() 可能早于 _ready(组件节点先被面板绑定):此时补一次刷新
	if target:
		refresh()

func _connect_signals():
	var stockpile: Stockpile = target as Stockpile
	if stockpile:
		stockpile.content_type_changed.connect(refresh)
		stockpile.stored_count_changed.connect(refresh)

func _disconnect_signals():
	var stockpile: Stockpile = target as Stockpile
	if stockpile:
		stockpile.content_type_changed.disconnect(refresh)
		stockpile.stored_count_changed.disconnect(refresh)

func refresh():
	var stockpile: Stockpile = target as Stockpile
	if not stockpile:
		return
	if _type_label:
		_type_label.text = stockpile.content_type
	if _stock_bar:
		var cap: int = stockpile.capacity
		var stock: int = stockpile.stored_count
		_stock_bar.max_value = maxi(cap, 1)
		_stock_bar.value = clampf(float(stock) / float(maxi(cap, 1)), 0.0, 1.0) * _stock_bar.max_value
	if _stock_label:
		_stock_label.text = "%d / %d" % [stockpile.stored_count, stockpile.capacity]
