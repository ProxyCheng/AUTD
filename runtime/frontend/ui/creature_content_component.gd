class_name CreatureContentComponent
extends InspectorComponent

# 生物内容组件:服务任意 Creature(Labor/Enemy/Slime)—— 显示状态行 + 生命条/生命值。
# 只读 backend 可观察状态(§5.4):状态随 entity.state_changed 刷新、生命随
# creature.health_changed 刷新,每次 refresh() 全量重读,不缓存。工人专属的随身仓/
# 装载内容不在这里,由 LaborContentComponent 负责(工人面板会同时绑定两个组件)。

# creature.state 取值 → 面板文案。取值集合来自 backend(不猜):creature.gd(dizzy/die)、
# idle_task.gd(idle)、move_to_target_task.gd(walk)、provide_workload_task.gd(work);
# 未列出的取值原样回显,不吞新状态。  # { state: 显示文案 }
const STATUS_TEXT: Dictionary = {
	"idle": "Idle",
	"walk": "Walking",
	"work": "Working",
	"dizzy": "Stunned",
	"die": "Down",
}

var _status_label: Label = null
var _health_bar: ProgressBar = null
var _health_label: Label = null
var _health_fill: StyleBoxFlat = null

func supports(in_target: Object) -> bool:
	return in_target is Creature

func _ready():
	_status_label = get_node_or_null("%StatusLabel") as Label
	_health_bar = get_node_or_null("%HealthBar") as ProgressBar
	_health_label = get_node_or_null("%HealthLabel") as Label
	# 生命条与头顶 EntityHealthBar 同色:取本实例私有样式,具体阵营色在 refresh() 里定
	if _health_bar:
		_health_fill = apply_bar_fill(_health_bar, EntityHealthBar.COLOR_FRIENDLY)
	# bind() 可能早于 _ready(组件节点先被面板绑定):此时补一次刷新
	if target:
		refresh()

func _connect_signals():
	var creature: Creature = target as Creature
	if not is_instance_valid(creature):
		return
	creature.state_changed.connect(refresh)
	creature.health_changed.connect(refresh)

func _disconnect_signals():
	var creature: Creature = target as Creature
	if not is_instance_valid(creature):
		return
	creature.state_changed.disconnect(refresh)
	creature.health_changed.disconnect(refresh)

func refresh():
	var creature: Creature = target as Creature
	if not is_instance_valid(creature):
		return
	if _status_label:
		_status_label.text = STATUS_TEXT.get(creature.state, creature.state)
	# max_health 可能为 0(数据未配),按 1 兜底避免除零;health 可能为负(致命伤),
	# 经 clamp 落到条底,不把条画反。
	var max_health: float = maxf(creature.max_health, 1.0)
	if _health_bar:
		_health_bar.max_value = max_health
		_health_bar.value = clampf(creature.health / max_health, 0.0, 1.0) * max_health
		if _health_fill:
			# 与头顶血条同色:敌对红 / 友方绿
			_health_fill.bg_color = EntityHealthBar.color_for(creature)
	if _health_label:
		_health_label.text = "%d / %d" % [roundi(creature.health), roundi(creature.max_health)]
