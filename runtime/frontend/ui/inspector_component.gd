class_name InspectorComponent
extends Control

# 建筑检视面板的可插拔组件基类:哑表现(AGENTS §1/§6) —— 只读 backend 可观察状态、
# 经公开方法改状态;通过 supports() 声明自己服务的建筑类型;绑定后自行监听 backend 信号
# 刷新(§5.4),不由面板级联 —— 面板只管绑定/解绑与标题。
#
# 组件是独立场景的根节点(子类脚本挂在各自 .tscn 根上),内部节点用 %Name 解析自己的
# 场景;面板不得窥探组件内部节点(AGENTS §6)。
#
# 生命周期(由 BuildingInspectorPanel 驱动):
#   bind(in_building)  先 unbind() 清旧连接;supports() 不通过则隐藏并返回 false;
#                      通过则记 building → _connect_signals() → refresh() → show()
#   unbind()           _disconnect_signals()(此时 building 仍有效,组件清空内部数据时
#                      可能回放一次落库回调,见 RecipeListComponent)→ 清 building → hide()

var building: Building = null

# 是否服务该建筑(子类用 is 收窄,如 return in_building is Workshop)。
func supports(in_building: Building) -> bool:
	return false

# 绑定建筑:返回是否成功;不支持的建筑返回 false 并保持隐藏。
func bind(in_building: Building) -> bool:
	unbind()
	if in_building == null or not supports(in_building):
		hide()
		return false
	building = in_building
	_connect_signals()
	refresh()
	show()
	return true

# 解绑:先断开 backend 信号(此时 building 仍有效),再清引用并隐藏。
func unbind():
	if building:
		_disconnect_signals()
	building = null
	hide()

# 连接 backend 可观察信号(子类覆写;调用时 building 保证有效)。
func _connect_signals():
	pass

# 断开 backend 可观察信号(子类覆写;调用时 building 保证有效)。
func _disconnect_signals():
	pass

# 全量刷新一次(子类覆写:依据 building 当前状态重排 UI)。
func refresh():
	pass
