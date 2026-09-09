class_name BuildingInspectorPanel
extends Control

# 建筑检视面板基类(屏幕空间侧栏,挂在 battle.tscn %inspector 下)。
# 一屏只检视一个建筑,同类型面板复用:"configure(in_building) 绑定新对象,GUI 经
# backend 公开方法改状态,backend 信号回流刷新" —— 绑定前先 disconnect 旧连接再
# connect(防重绑重复回调),与 actor 的 bind 约定一致。
#
# 面板是"哑"组件:只暴露 configure(in_building)/close()/closed 信号,由 LevelActor /
# InspectMode 连接处理;不直接持有玩法状态,只依赖 backend 可观察信号刷新。
#
# 子类约定:
#   make_title(in_building) -> String   面板标题(建筑类型名)
#   _refresh()                          全量刷新一次(连信号后调用;子类覆写)
#   以及按需 connect 的 backend 信号在 _connect_signals/_disconnect_signals 里管理。
# 基类负责通用装配:标题、关闭按钮、绑定信号生命周期。

signal closed()
# 点击 Delete 按钮:请求删除当前检视的建筑(由 LevelActor 监听处理;面板本身不删)。
signal delete_requested(building: Building)

var building: Building = null
var _title_label: Label = null
var _close_button: Button = null
var _delete_button: Button = null

# 绑定检视对象:先解绑旧连接再全量刷新(防重绑重复回调)。
func configure(in_building: Building):
	_disconnect_signals()
	building = in_building
	if not is_inside_tree():
		# _ready 前必须延后到节点树就绪
		call_deferred(&"_configure_post_ready", in_building)
		return
	_configure_post_ready(in_building)

func _configure_post_ready(in_building: Building):
	building = in_building
	if building == null:
		return
	_ensure_widgets()
	if _title_label:
		_title_label.text = make_title(building)
	_connect_signals()
	_refresh()
	show()

# 绑定 backend 信号(子类覆写,内部自行 connect;记得记录到 _my_connections 供断开)。
func _connect_signals():
	pass

# 解绑全部 backend 信号(子类覆写,对应断开 _connect_signals 里连的)。
func _disconnect_signals():
	pass

# 全量刷新一次(子类覆写:依据 building 当前数据重排 UI)。
func _refresh():
	pass

# 标题(子类覆写:返回建筑显示名,如 "Crossbow"/"Crafting Workshop")。
func make_title(in_building: Building) -> String:
	return in_building.type

# 关闭检视(清空绑定,发 closed 信号,隐藏)。LevelActor/InspectMode 经此退出检视。
func close():
	_disconnect_signals()
	building = null
	hide()
	closed.emit()

# —— 通用装配(子类 _ready 里先调 super) ——

func _ready():
	_ensure_widgets()

func _ensure_widgets():
	if _title_label:
		return
	# 若 .tscn 未预置标题/关闭钮,这里兜底建最小 UI(纯逻辑版本无 .tscn 时仍可用)
	_title_label = get_node_or_null("Title") as Label
	_close_button = get_node_or_null("CloseButton") as Button
	_delete_button = get_node_or_null("DeleteButton") as Button
	if _close_button and not _close_button.pressed.is_connected(_on_close_pressed):
		_close_button.pressed.connect(_on_close_pressed)
	if _delete_button and not _delete_button.pressed.is_connected(_on_delete_pressed):
		_delete_button.pressed.connect(_on_delete_pressed)
	hide()

func _on_close_pressed():
	close()

# 删除按钮:发出 delete_requested(building) 交由 LevelActor 处理(关面板+销毁建筑)。
# 面板本身不删建筑(哑组件,只表达意图,经信号回调),遵循 AGENTS §6 约定。
func _on_delete_pressed():
	if not building:
		return
	delete_requested.emit(building)
