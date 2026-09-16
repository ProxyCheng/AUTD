class_name BuildingInspectorPanel
extends Control

# 通用建筑检视面板(屏幕空间侧栏,挂在 battle.tscn %inspector/Panel 下)。
# 一屏只检视一个建筑:面板自身不含任何建筑专属 UI,只做三件事 ——
#   1. 绑定/解绑 %Components 下的全部 InspectorComponent:组件各自 supports() 声明
#      服务的建筑类型、自行监听 backend 信号刷新(见 inspector_component.gd),
#      面板不按类型路由、不窥探组件内部;
#   2. 标题(make_title:建筑类型 → 显示名);
#   3. 关闭(×)/删除按钮的意图信号。
# 组件组合可自由调整:在 building_inspector_panel.tscn 的 %Components 里增删组件即可。
#
# 对外契约(LevelActor / InspectMode / BuildingInspectorHost 依赖):
#   configure(in_building) -> bool   绑定并显示;无组件支持该建筑时返回 false 且不显示
#   close()                          解绑、隐藏、发 closed
#   signal closed / delete_requested(building)

signal closed()
# 点击 Delete 按钮:请求删除当前检视的建筑(由 LevelActor 监听处理;面板本身不删)。
signal delete_requested(building: Building)

# 建筑类型 → 面板标题(保持历史显示名);未列出的类型回退为 type.capitalize()。
const TITLES: Dictionary = {
	"crafting_workshop": "Workshop",
	"tree_workshop": "Workshop",
	"stone_mine": "Workshop",
	"crossbow": "Crossbow",
	"cannon": "Cannon",
	"stockpile": "Stockpile",
}

var building: Building = null
var _title_label: Label = null
var _close_button: Button = null
var _delete_button: Button = null
var _components: Array[InspectorComponent] = []

# 绑定检视对象:先解绑旧组件再绑定新建筑;全部组件都不支持时返回 false(不显示)。
func configure(in_building: Building) -> bool:
	_ensure_widgets()
	_ensure_components()
	_unbind_components()
	building = in_building
	if building == null:
		hide()
		return false
	var bound_any: bool = false
	for component: InspectorComponent in _components:
		if component.bind(building):
			bound_any = true
	if not bound_any:
		building = null
		hide()
		return false
	if _title_label:
		_title_label.text = make_title(building)
	show()
	return true

# 关闭检视(清空绑定,发 closed 信号,隐藏)。LevelActor/InspectMode 经此退出检视。
func close():
	_ensure_components()
	_unbind_components()
	building = null
	hide()
	AudioManager.sfx(&"ui_close")
	closed.emit()

# 标题(类型 → 显示名;未列出的类型回退 type.capitalize())。
func make_title(in_building: Building) -> String:
	return TITLES.get(in_building.type, in_building.type.capitalize())

# —— 通用装配 ——

func _ready():
	_ensure_widgets()
	_ensure_components()
	# configure 可能早于 _ready(组件节点尚未就绪):这里补一次绑定
	if building:
		configure(building)

func _ensure_widgets():
	if _title_label:
		return
	_title_label = get_node_or_null("%Title") as Label
	_close_button = get_node_or_null("%CloseButton") as Button
	_delete_button = get_node_or_null("%DeleteButton") as Button
	if _close_button and not _close_button.pressed.is_connected(_on_close_pressed):
		_close_button.pressed.connect(_on_close_pressed)
	if _delete_button and not _delete_button.pressed.is_connected(_on_delete_pressed):
		_delete_button.pressed.connect(_on_delete_pressed)
	hide()

# 收集 %Components 下的组件(懒收集:configure/close 可能在 _ready 前调用)。
func _ensure_components():
	if not _components.is_empty():
		return
	var container: Control = get_node_or_null("%Components") as Control
	if not container:
		return
	for child: Node in container.get_children():
		var component: InspectorComponent = child as InspectorComponent
		if component:
			_components.append(component)

func _unbind_components():
	for component: InspectorComponent in _components:
		component.unbind()

func _on_close_pressed():
	close()

# 删除按钮:发出 delete_requested(building) 交由 LevelActor 处理(关面板+销毁建筑)。
# 面板本身不删建筑(哑组件,只表达意图,经信号回调),遵循 AGENTS §6 约定。
func _on_delete_pressed():
	if not building:
		return
	AudioManager.sfx(&"ui_click")
	delete_requested.emit(building)
