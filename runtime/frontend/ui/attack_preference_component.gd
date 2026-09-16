class_name AttackPreferenceComponent
extends InspectorComponent

# 攻击倾向组件:服务一切 AttackBuilding(弩炮/火炮)。
# 显示"目标偏好"标签 + 下拉框;控件变化经 set_target_preference() 落后端
# (§5.4 可观察属性),后端 target_preference_changed 回流刷新 —— 不轮询、不直改。

# 下拉项文本索引 → 后端取值映射(与 AttackBuilding 常量对齐)。
const _PREF_VALUE: Array[String] = [
	AttackBuilding.TARGET_PREF_NEAREST,
	AttackBuilding.TARGET_PREF_FRONT,
	AttackBuilding.TARGET_PREF_STRONGEST,
]

var _option: OptionButton = null

func supports(in_target: Object) -> bool:
	return in_target is AttackBuilding

func _ready():
	_option = get_node_or_null("%PreferenceOption") as OptionButton
	if _option:
		_option.clear()
		_option.add_item("Nearest", 0)      # item_text 显示名;对应 AttackBuilding.TARGET_PREF_NEAREST
		_option.add_item("Front", 1)
		_option.add_item("Strongest", 2)
		if not _option.item_selected.is_connected(_on_option_selected):
			_option.item_selected.connect(_on_option_selected)
	# bind() 可能早于 _ready(组件节点先被面板绑定):此时补一次刷新
	if target:
		refresh()

func _connect_signals():
	var attack: AttackBuilding = target as AttackBuilding
	if attack:
		attack.target_preference_changed.connect(refresh)

func _disconnect_signals():
	var attack: AttackBuilding = target as AttackBuilding
	if attack:
		attack.target_preference_changed.disconnect(refresh)

func refresh():
	if not _option:
		return
	var attack: AttackBuilding = target as AttackBuilding
	if not attack:
		return
	# 同步 UI 到 backend 当前偏好
	var idx: int = _PREF_VALUE.find(attack.target_preference)
	_option.select(idx if idx >= 0 else 0)

# 控件变化 → 调 backend 公开方法落状态(经 setter → 信号回流 refresh)。
func _on_option_selected(in_index: int):
	var attack: AttackBuilding = target as AttackBuilding
	if not attack:
		return
	if in_index < 0 or in_index >= _PREF_VALUE.size():
		return
	attack.set_target_preference(_PREF_VALUE[in_index])
