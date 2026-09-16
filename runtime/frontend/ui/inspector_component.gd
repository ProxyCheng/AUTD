class_name InspectorComponent
extends Control

# 检视面板的可插拔组件基类:哑表现(AGENTS §1/§6) —— 只读 backend 可观察状态、
# 经公开方法改状态;通过 supports() 声明自己服务的检视目标类型(Building 或 Entity);
# 绑定后自行监听 backend 信号刷新(§5.4),不由面板级联 —— 面板只管绑定/解绑与标题。
#
# 组件是独立场景的根节点(子类脚本挂在各自 .tscn 根上),内部节点用 %Name 解析自己的
# 场景;面板不得窥探组件内部节点(AGENTS §6)。
#
# 生命周期(由 BuildingInspectorPanel 驱动):
#   bind(in_target)    先 unbind() 清旧连接;supports() 不通过则隐藏并返回 false;
#                      通过则记 target → _connect_signals() → refresh() → show()
#   unbind()           _disconnect_signals()(此时 target 仍有效,组件清空内部数据时
#                      可能回放一次落库回调,见 RecipeListComponent)→ 清 target → hide()

# 检视目标(Building 或 Entity);子类用 supports() 收窄。
var target: Object = null

# 是否服务该检视目标(子类用 is 收窄,如 return in_target is Workshop)。
func supports(in_target: Object) -> bool:
	return false

# 绑定检视目标:返回是否成功;不支持的目标返回 false 并保持隐藏。
func bind(in_target: Object) -> bool:
	unbind()
	if in_target == null or not supports(in_target):
		hide()
		return false
	target = in_target
	_connect_signals()
	refresh()
	show()
	return true

# 解绑:先断开 backend 信号(此时 target 仍有效),再清引用并隐藏。
func unbind():
	if is_instance_valid(target):
		_disconnect_signals()
	target = null
	hide()

# 连接 backend 可观察信号(子类覆写;调用时 target 保证有效)。
func _connect_signals():
	pass

# 断开 backend 可观察信号(子类覆写;调用时 target 保证有效)。
func _disconnect_signals():
	pass

# 全量刷新一次(子类覆写:依据 target 当前状态重排 UI)。
func refresh():
	pass
