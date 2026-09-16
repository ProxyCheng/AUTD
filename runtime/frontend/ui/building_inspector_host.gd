class_name BuildingInspectorHost
extends Control

# 检视面板宿主(挂在 battle.tscn %inspector/Panel 上):一屏检视一个建筑。
# 本容器只做两件事:把 configure/close 转发给唯一子面板(BuildingInspectorPanel),
# 并把面板的 closed / delete_requested 级联回 LevelActor —— 不再按类型选面板,
# 面板自己按组件 supports() 决定能否显示(见 building_inspector_panel.gd)。
#
# LevelActor.inspect_building 调本容器 configure(in_building),返回是否成功开启;
# close_inspector 调 close();面板 × 关闭经 closed → owner.close_inspector 回 roaming。

var _closing: bool = false   # 防重入 guard,避免 close_inspector 级联递归
var _panel: BuildingInspectorPanel = null

# 绑定建筑:转发给面板;返回 true 表示成功开启检视(有组件支持该建筑),false = 无可检视内容。
func configure(in_building: Building) -> bool:
	_ensure_panel()
	if not _panel:
		return false
	return _panel.configure(in_building)

# 关闭当前检视(LevelActor.close_inspector 调用,或面板关闭按钮 × 级联后进入)。
func close():
	if _closing:
		return
	_closing = true
	if _panel and _panel.visible:
		_panel.close()
	_closing = false

func _ready():
	_ensure_panel()

# 找到(并缓存)唯一子面板:初次调用时完成隐藏与信号接线(configure 可能早于 _ready)。
func _ensure_panel():
	if _panel and is_instance_valid(_panel):
		return
	for child in get_children():
		var panel: BuildingInspectorPanel = child as BuildingInspectorPanel
		if panel:
			_panel = panel
			panel.hide()
			if not panel.closed.is_connected(_on_panel_closed):
				panel.closed.connect(_on_panel_closed)
			if not panel.delete_requested.is_connected(_on_panel_delete_requested):
				panel.delete_requested.connect(_on_panel_delete_requested)
			return

# 面板被关闭(×):级联 LevelActor.close_inspector 回 roaming。
func _on_panel_closed():
	if _closing:
		return
	owner.close_inspector()

# 面板点 Delete:级联 LevelActor.delete_building(building)(销毁建筑),再由其关闭面板。
func _on_panel_delete_requested(in_building: Building):
	if _closing:
		return
	if owner.has_method(&"delete_building"):
		owner.call(&"delete_building", in_building)
