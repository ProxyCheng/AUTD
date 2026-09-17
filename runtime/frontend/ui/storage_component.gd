class_name StorageComponent
extends InspectorComponent

# 主基地仓储组件:服务 MainBase —— 逐类型列出兜底仓(bag)的内容物,一行 "类型  件数"。
# 只读 backend 可观察状态(§5.4):Bag 没有"按类型变化"信号,count_changed 是唯一的内容
# 变化通知,故 refresh() 每次重读 types()/count_of(),不缓存(同 LaborContentComponent)。
#
# 与 StockpileContentComponent 的唯一刻意差异:主基地仓是无上限仓
# (max_count == Bag.UNLIMITED == -1),容量语义不存在 —— 不画容量条、不显示 "N / M"、
# 不做任何按 max_count 的除法或比例换算(那些数字对无限仓毫无意义)。
#
# 行池:count_changed 触发频繁,refresh() 只复用现有行改文本,绝不整表重建(§5.5)。

var _rows_container: VBoxContainer = null
# 隐藏的行模板(样式/字号在场景里声明);刷新时按需 duplicate 出行,只增不减
var _row_template: Label = null
var _empty_label: Label = null
# 行池:索引与当前 types() 顺序一一对应;多余的隐藏待复用
var _rows: Array[Label] = []
# 已连接的展示仓:断连用它而非重新 get_display_bag() —— 重绑期间若仓实例更换,
# 重新取会断不到旧连接、回调叠加(AGENTS §5.5)
var _bag: Bag = null

func supports(in_target: Object) -> bool:
	return in_target is MainBase

func _ready():
	_ensure_widgets()
	# bind() 可能早于 _ready(组件节点先被面板绑定):此时补一次刷新
	if target:
		refresh()

# 懒解析场景内部节点(与 BuildingInspectorPanel._ensure_widgets 同型):bind 可能早于 _ready
func _ensure_widgets():
	if _rows_container:
		return
	_rows_container = get_node_or_null("%Rows") as VBoxContainer
	_row_template = get_node_or_null("%RowTemplate") as Label
	_empty_label = get_node_or_null("%EmptyLabel") as Label

func _connect_signals():
	var bag: Bag = _display_bag()
	if not is_instance_valid(bag):
		return
	# 先断旧连接再连:重绑绝不叠加回调(AGENTS §5.5)
	if is_instance_valid(_bag) and _bag.count_changed.is_connected(refresh):
		_bag.count_changed.disconnect(refresh)
	_bag = bag
	if not _bag.count_changed.is_connected(refresh):
		_bag.count_changed.connect(refresh)

func _disconnect_signals():
	if is_instance_valid(_bag) and _bag.count_changed.is_connected(refresh):
		_bag.count_changed.disconnect(refresh)
	_bag = null

func refresh():
	_ensure_widgets()
	if not _rows_container or not _row_template:
		return
	# 全量重读、不缓存:缓存会漏掉 take_state/add_state 这类"只搬实例"的仓内容变化
	var lines: Array[String] = []
	var bag: Bag = _display_bag()
	if is_instance_valid(bag):
		for item_type: String in bag.types():
			lines.append("%s  %d" % [item_type, bag.count_of(item_type)])
	_sync_rows(lines.size())
	for i in lines.size():
		_rows[i].text = lines[i]

# 展示仓:经 has_method 鸭子探测 get_display_bag(),组件不硬依赖该字段的落地时序;
# 无 target / 无仓时返回 null,由 refresh() 按空仓渲染。
func _display_bag() -> Bag:
	if not is_instance_valid(target) or not target.has_method(&"get_display_bag"):
		return null
	return target.call(&"get_display_bag") as Bag

# 行池同步:只增行、复用现有行改文本;类型变少只隐藏多余行,绝不整表重建。
func _sync_rows(in_count: int):
	while _rows.size() < in_count:
		var row: Label = _row_template.duplicate() as Label
		# 模板开 unique_name_in_owner 供 %RowTemplate 解析;副本必须关掉,防 % 重名冲突
		row.unique_name_in_owner = false
		row.visible = true
		_rows_container.add_child(row)
		_rows.append(row)
	for i in _rows.size():
		_rows[i].visible = i < in_count
	if _empty_label:
		_empty_label.visible = in_count == 0
