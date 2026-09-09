class_name CrossbowInspectorPanel
extends BuildingInspectorPanel

# 弩炮检视面板:配置攻击倾向(最前/最近/最强)。GUI 修改经 Crossbow.set_target_preference()
# 落后端(走 §5.4 可观察属性),后端经 target_preference_changed 回流刷新 UI —— 不轮询、不直改。

var _preference_option: OptionButton = null

func make_title(in_building: Building) -> String:
	return "Crossbow"

# 覆盖基类 _ready:先让基类装配(标题/关闭钮),再建攻击倾向控件。
func _ready():
	super()
	_ensure_preference_widget()

func _ensure_preference_widget():
	_preference_option = get_node_or_null("PreferenceOption") as OptionButton
	if not _preference_option:
		return
	if _preference_option.item_count > 0:
		return
	_preference_option.clear()
	_preference_option.add_item("Nearest", 0)      # item_text 显示名;对应 Crossbow.TARGET_PREF_NEAREST
	_preference_option.add_item("Front", 1)
	_preference_option.add_item("Strongest", 2)
	if not _preference_option.item_selected.is_connected(_on_preference_option_selected):
		_preference_option.item_selected.connect(_on_preference_option_selected)

# _preference_option 的文本索引 → 后端取值映射(与 Crossbow 常量对齐)。
const _PREF_VALUE: Array[String] = [
	Crossbow.TARGET_PREF_NEAREST,
	Crossbow.TARGET_PREF_FRONT,
	Crossbow.TARGET_PREF_STRONGEST,
]

func _connect_signals():
	if building:
		building.target_preference_changed.connect(_on_target_preference_changed)

func _disconnect_signals():
	if building:
		building.target_preference_changed.disconnect(_on_target_preference_changed)

func _refresh():
	if not building:
		return
	# 同步 UI 到 backend 当前偏好
	var idx: int = _PREF_VALUE.find(building.target_preference)
	_preference_option.select(idx if idx >= 0 else 0)

# 控件变化 → 调 backend 公开方法落状态(经 setter → 信号回流 _on_target_preference_changed)。
func _on_preference_option_selected(in_index: int):
	if not building:
		return
	building.set_target_preference(_PREF_VALUE[in_index])

# backend 信号回流 → 若与当前控件不同则刷新(通常由 setter 触发,这里兜底保证一致)。
func _on_target_preference_changed():
	_refresh()
