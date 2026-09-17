class_name PriorityComponent
extends InspectorComponent

# 优先级组件:服务一切"派活优先级"建筑 —— Workshop 及其 AttackBuilding/Turret 子类
# (工人调度按 Building.priority 排序派活)。显示"Priority"标签 + 下拉框(1..9);
# 控件变化经 Building.priority 属性 setter 落后端(§5.4 可观察属性),
# 后端 priority_changed 回流刷新 —— 不轮询、不直改。

const _MIN_PRIORITY: int = 1
const _MAX_PRIORITY: int = 9

var _option: OptionButton = null

func supports(in_target: Object) -> bool:
	return in_target is Workshop

func _ready():
	_option = get_node_or_null("%PriorityOption") as OptionButton
	if _option:
		_option.clear()
		# item_text = 显示数字,item_id = 取值本身;索引与值相差 _MIN_PRIORITY
		for value: int in range(_MIN_PRIORITY, _MAX_PRIORITY + 1):
			_option.add_item(str(value), value)
		if not _option.item_selected.is_connected(_on_option_selected):
			_option.item_selected.connect(_on_option_selected)
	# bind() 可能早于 _ready(组件节点先被面板绑定):此时补一次刷新
	if target:
		refresh()

func _connect_signals():
	var building: Building = target as Building
	if building:
		building.priority_changed.connect(refresh)

func _disconnect_signals():
	var building: Building = target as Building
	if building:
		building.priority_changed.disconnect(refresh)

func refresh():
	if not _option:
		return
	var building: Building = target as Building
	if not building:
		return
	# 同步 UI 到 backend 当前优先级(下拉索引 = 值 - _MIN_PRIORITY,越界由 backend clamp 兜底)
	_option.select(clampi(building.priority - _MIN_PRIORITY, 0, _MAX_PRIORITY - _MIN_PRIORITY))

# 控件变化 → 经属性 setter 落后端(clamp 与信号回流 refresh 由 backend 负责)。
func _on_option_selected(in_index: int):
	var building: Building = target as Building
	if not building:
		return
	building.priority = in_index + _MIN_PRIORITY
