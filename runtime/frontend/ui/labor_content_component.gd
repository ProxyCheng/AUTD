class_name LaborContentComponent
extends InspectorComponent

# 工人内容组件:服务 Labor —— 显示头顶货仓(head_bag,装载)与手上仓(hand_bag,工具)
# 的内容(类型/件数,工具另附耐久)与装载条(装载比例取 head_bag);
# 状态行与生命值由 CreatureContentComponent 负责(工人面板会同时绑定两个组件)。
# 只读 backend 可观察状态(§5.4):头顶货仓是多类型仓,Bag 没有"按类型变化"信号,
# count_changed 是唯一的内容变化通知,故 refresh() 每次重读 types()/count_of()/
# peek_state(),不缓存内容 —— 否则会漏掉 take_state/add_state 的搬动。

var _bag_label: Label = null
var _load_bar: ProgressBar = null
var _load_label: Label = null

func supports(in_target: Object) -> bool:
	return in_target is Labor

func _ready():
	_bag_label = get_node_or_null("%BagLabel") as Label
	_load_bar = get_node_or_null("%LoadBar") as ProgressBar
	_load_label = get_node_or_null("%LoadLabel") as Label
	# bind() 可能早于 _ready(组件节点先被面板绑定):此时补一次刷新
	if target:
		refresh()

func _connect_signals():
	var labor: Labor = target as Labor
	if not is_instance_valid(labor):
		return
	# 内容跨两仓:头顶货仓(head_bag)记装载,手上仓(hand_bag)记那件工具 —— 两仓的信号都要听。
	var head: Bag = labor.head_bag
	if is_instance_valid(head):
		head.count_changed.connect(refresh)
		head.item_type_changed.connect(refresh)
	var hand: Bag = labor.hand_bag
	if is_instance_valid(hand):
		hand.count_changed.connect(refresh)
		hand.item_type_changed.connect(refresh)

func _disconnect_signals():
	var labor: Labor = target as Labor
	if not is_instance_valid(labor):
		return
	var head: Bag = labor.head_bag
	if is_instance_valid(head):
		head.count_changed.disconnect(refresh)
		head.item_type_changed.disconnect(refresh)
	var hand: Bag = labor.hand_bag
	if is_instance_valid(hand):
		hand.count_changed.disconnect(refresh)
		hand.item_type_changed.disconnect(refresh)

func refresh():
	var labor: Labor = target as Labor
	if not is_instance_valid(labor):
		return
	# head_bag / hand_bag 都在 Labor._ready() 里才创建:绑定早于它们时按空仓/零装载渲染。
	var head: Bag = labor.head_bag
	var hand: Bag = labor.hand_bag
	if _bag_label:
		_bag_label.text = _content_text(head, hand)
	if not is_instance_valid(head):
		if _load_bar:
			_load_bar.value = 0.0
		if _load_label:
			_load_label.text = "0 / 0"
		return
	# 装载比例用头顶货仓(head_bag)整仓 count(各类型求和)—— 多类型装载下
	# count_of(item_type) 只算主类型,会漏计。
	var cap: int = maxi(head.max_count, 1)
	if _load_bar:
		_load_bar.max_value = float(cap)
		_load_bar.value = clampf(float(head.count) / float(cap), 0.0, 1.0) * float(cap)
	if _load_label:
		_load_label.text = "%d / %d" % [head.count, head.max_count]

# 内容文本:头顶货仓(head_bag,装载)与手上仓(hand_bag,工具)各按类型列一行,空仓不占行。
func _content_text(in_head: Bag, in_hand: Bag) -> String:
	var lines: Array[String] = []
	var bags: Array[Bag] = [in_head, in_hand]
	for bag: Bag in bags:
		if not is_instance_valid(bag):
			continue
		var text: String = _bag_text(bag)
		if not text.is_empty():
			lines.append(text)
	return "\n".join(lines)

# 单仓内容文本:每类型一行 "<type>  <count>";该类型有状态单体(工具)再追加耐久。
func _bag_text(in_bag: Bag) -> String:
	var lines: Array[String] = []
	for item_type: String in in_bag.types():
		var line: String = "%s  %d" % [item_type, in_bag.count_of(item_type)]
		var carrier: Object = in_bag.peek_state(item_type)
		# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;在 freed 实例上做 `is` 会崩
		# (同 Bag._drop_entry 的注释,§5.8)。
		if is_instance_valid(carrier) and carrier is Tool:
			var tool: Tool = carrier
			line += "  durability %d/%d" % [roundi(tool.durability), roundi(tool.max_durability)]
		lines.append(line)
	return "\n".join(lines)
