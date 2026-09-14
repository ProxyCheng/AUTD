class_name CannonInspectorPanel
extends CrossbowInspectorPanel

# 火炮检视面板:与弩炮面板完全同构(攻击倾向下拉 + 配方列表 + 进度 + 删除),只换标题。
# Cannon 是 Crossbow 子类,攻击倾向/配方机制全部继承,故面板直接复用基类实现,
# 无需重复装配控件或信号 —— 见 crossbow_inspector_panel.gd。
func make_title(_in_building: Building) -> String:
	return "Cannon"
