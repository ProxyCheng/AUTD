class_name WorkshopInspectorPanel
extends BuildingInspectorPanel

# 作坊检视面板:展示配方列表 + 每张配方的进度/启停态,并支持拖动调整排序以改变执行优先级。
# 排序经 Workshop.move_recipe(from, to) 落后端(backend 持有 recipes 数组作为唯一"顺序真相"),
# 后端经 recipe_order_changed 回流刷新 —— 前端不复制排序/玩法状态(AGENTS §1)。
#
# 拖放机制:RecipeList(VBoxContainer, workshop_recipe_list.gd)是拖放目标(实现
# _can_drop_data/_drop_data);每行(workshop_recipe_row.gd)是拖拽源(实现 _get_drag_data)。
# 列表容器回调会把拖拽结果传给本面板,经 move_recipe 落库。
#
# 布局约定(与 .tscn 节点对应;纯逻辑无 .tscn 时按名兜底,可能退化为空列表):
#   Title       Label          标题
#   CloseButton Button         关闭钮
#   RecipeList  VBoxContainer  配方列表(每行一个 WorkshopRecipeRow)

var _recipe_list: VBoxContainer = null

func make_title(in_building: Building) -> String:
	return "Workshop"

func _ready():
	super()
	_recipe_list = get_node_or_null("RecipeList") as VBoxContainer
	if _recipe_list and _recipe_list.has_signal(&"recipe_dropped"):
		_recipe_list.recipe_dropped.connect(_on_recipe_list_dropped)

func _connect_signals():
	if not building:
		return
	# 顺序/当前执行配方变化 → 整列表重建与高亮;进度高频刷新由行 _process 自读,不在此重建
	# (避免每帧重建拖拽列表、打断拖放)。
	building.recipe_order_changed.connect(_refresh)
	building.active_recipe_changed.connect(_refresh)

func _disconnect_signals():
	if not building:
		return
	building.recipe_order_changed.disconnect(_refresh)
	building.active_recipe_changed.disconnect(_refresh)

func _refresh():
	if not building or not _recipe_list:
		return
	if not _recipe_list.has_method(&"populate"):
		return
	_recipe_list.call(&"populate", building)

# 列表容器经 recipe_dropped 上报拖放结果(from -> to),调 backend 落库。
func _on_recipe_list_dropped(in_from_index: int, in_to_index: int):
	if not building:
		return
	building.move_recipe(in_from_index, in_to_index)
