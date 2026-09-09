class_name BuildingInspectorHost
extends Control

# 检视面板路由容器(挂在 battle.tscn %inspector/Panel 上):一屏检视一个建筑,
# 按建筑类型路由到对应子面板(CrossbowPanel/WorkshopPanel),其余隐藏。
#
# LevelActor.inspect_building 调本容器 configure(in_building),返回是否成功开启(有对应面板);
# close_inspector 调 close();子面板关闭(×)经本容器级联 owner.close_inspector 回 roaming。
#
# 路由要点:先判 is Crossbow 再判 is Workshop(crossbow 继承 workshop,顺序不能反),
# 无对应面板的建筑(main_base/enemy_spawner/stockpile)返回 false 保持 roaming。

var _closing: bool = false   # 防重入 guard,避免 close_inspector 级联递归

# 绑定建筑:按类型选子面板 show 并转发 configure,其余 hide。
# 返回 true 表示成功开启检视(有可显示面板);false = 无可检视内容(调用方不应切模式)。
func configure(in_building: Building) -> bool:
	var chosen: Control = _select_panel(in_building)
	if chosen == null:
		return false
	for child in get_children():
		if child is BuildingInspectorPanel:
			child.visible = (child == chosen)
	if chosen.has_method(&"configure"):
		chosen.call(&"configure", in_building)
	return true

# 按建筑类型选子面板(Crossbow 先于 Workshop)。
func _select_panel(in_building: Building) -> Control:
	if in_building is Crossbow:
		return get_node_or_null("CrossbowPanel")
	if in_building is Workshop:
		return get_node_or_null("WorkshopPanel")
	return null

# 关闭当前检视(LevelActor.close_inspector 调用,或关闭按钮 × 级联后进入)。
func close():
	if _closing:
		return
	_closing = true
	for child in get_children():
		if child is BuildingInspectorPanel and child.visible and child.has_method(&"close"):
			child.call(&"close")
	_closing = false

func _ready():
	# 初始全隐藏子面板;监听各子面板 closed(× 按钮)以级联回 roaming
	for child in get_children():
		if child is BuildingInspectorPanel:
			child.hide()
			if not child.closed.is_connected(_on_child_closed):
				child.closed.connect(_on_child_closed)

# 任一子面板被关闭(×):级联 LevelActor.close_inspector 回 roaming。
func _on_child_closed():
	if _closing:
		return
	owner.close_inspector()
