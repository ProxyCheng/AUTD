class_name RecipeListComponent
extends InspectorComponent

# 配方列表组件:服务一切 Workshop(含其子类 Crossbow/Cannon —— 攻击也是一张配方)。
# 根 = VBoxContainer:Hint(顶部固定)+ RecipeList(WorkshopRecipeList,吃掉剩余高度)。
#
# 列表(workshop_recipe_list.gd)是拖放目标并自管行的槽位布局;本组件只做两件事:
#   1. 把列表的 recipe_dropped(from, to) 落到 backend(Workshop.move_recipe,backend
#      recipes 是唯一顺序真相,组件不存本地顺序);
#   2. 拖拽期间推迟 backend 信号触发的整表重建(重建会释放正在被拖的行),等列表
#      drag_finished 后补一次 —— 该守卫从旧 WorkshopInspectorPanel 原样搬来。
#
# 解绑顺序(关键):先断 backend 信号 → 再 _list.clear()(clear 会终结拖拽,若落位
# 动画被打断会补发一次 recipe_dropped,该回调必须命中仍有效的旧 building)→ 之后
# 基类 unbind() 才清 building 引用。

var _list: WorkshopRecipeList = null
# 拖拽期间到达的刷新请求:拖拽中重建会释放正在被拖的行,故推迟到 drag_finished 再刷
var _refresh_deferred: bool = false

func supports(in_building: Building) -> bool:
	return in_building is Workshop

func _ready():
	_list = get_node_or_null("%RecipeList") as WorkshopRecipeList
	if _list:
		_list.recipe_dropped.connect(_on_recipe_dropped)
		_list.drag_finished.connect(_on_drag_finished)
	# bind() 可能早于 _ready(组件节点先被面板绑定):此时补一次刷新
	if building:
		refresh()

func _connect_signals():
	var workshop: Workshop = building as Workshop
	if not workshop:
		return
	# 顺序/当前执行配方变化 → 整列表重建与高亮;进度高频刷新由行 _process 自读,不在此重建
	# (避免每帧重建拖拽列表、打断拖放)。
	workshop.recipe_order_changed.connect(refresh)
	workshop.active_recipe_changed.connect(refresh)

func _disconnect_signals():
	var workshop: Workshop = building as Workshop
	if not workshop:
		return
	workshop.recipe_order_changed.disconnect(refresh)
	workshop.active_recipe_changed.disconnect(refresh)
	# 清空配方列表:移除全部行并置空列表的 building 引用,防行 _process 在建筑释放后
	# 触碰已失效 building(freed instance)。重绑后 refresh 会重新 populate。
	# clear() 会终结进行中的拖拽;若落位动画被打断,列表先补发 recipe_dropped 再清空 ——
	# 此刻 building 引用尚未被基类清掉,_on_recipe_dropped 仍能落到旧建筑上。
	_refresh_deferred = false
	if _list:
		_list.clear()

func refresh():
	var workshop: Workshop = building as Workshop
	if not workshop or not _list:
		return
	if _list.is_dragging():
		# 拖拽/落位动画期间不重建:重建会释放正在被拖的行,动画与排序都会丢。
		# 拖拽期间 backend 仍可能发信号(如产线切换配方触发 active_recipe_changed),
		# 这些请求记为待刷,由 _on_drag_finished 在拖拽彻底结束后补一次。
		_refresh_deferred = true
		return
	_refresh_deferred = false
	_list.populate(workshop)

# 列表拖拽(含落位/回位动画)彻底结束 → 补做拖拽期间被推迟的刷新。
func _on_drag_finished():
	if _refresh_deferred:
		refresh()

# 列表经 recipe_dropped 上报拖放结果(from -> to),调 backend 落库。
func _on_recipe_dropped(in_from_index: int, in_to_index: int):
	var workshop: Workshop = building as Workshop
	if not workshop:
		return
	workshop.move_recipe(in_from_index, in_to_index)
