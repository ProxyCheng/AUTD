class_name WorkshopRecipeList
extends VBoxContainer

# 作坊面板的配方列表:负责渲染每张配方(WorkshopRecipeRow)并作为拖放目标。
# 拖放 target 协议:接受带 recipe_index 的拖拽数据,drop 时换算目标行索引,emit recipe_dropped,
# 由 WorkshopInspectorPanel 经 Workshop.move_recipe 落库。行本身作为拖拽源(见 workshop_recipe_row)。

signal recipe_dropped(from_index: int, to_index: int)

const ROW_SCENE_PATH: String = "res://runtime/frontend/ui/workshop_recipe_row.tscn"

var _building: Workshop = null

# 渲染某建筑的全部配方(每次全量重排,保证与 backend recipes 顺序一致)。
func populate(in_building: Workshop):
	_building = in_building
	_clear()
	if not _building:
		return
	var row_index: int = 0
	for recipe: RecipeData in _building.recipes:
		_append_row(recipe, row_index)
		row_index += 1

# 公开清空:移除全部配方行并重置 building 引用。
# 关闭面板/解绑时调用,避免行 _process 在建筑被释放后仍访问已失效 _building(freed instance)。
func clear():
	_building = null
	_clear()

func _clear():
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _append_row(in_recipe: RecipeData, in_index: int):
	var row: Control = null
	var scene: PackedScene = load(ROW_SCENE_PATH)
	if scene:
		row = scene.instantiate()
	if row == null:
		row = _make_fallback_row(in_recipe)
	row.set_meta(&"recipe_index", in_index)
	if row.has_method(&"setup"):
		var is_active: bool = _building.active_recipe == in_recipe
		row.call(&"setup", in_recipe, in_index, _building, is_active)
	if row.has_method(&"make_draggable"):
		row.call(&"make_draggable")
	add_child(row)
	row.custom_minimum_size = Vector2(0, 64)

func _make_fallback_row(in_recipe: RecipeData) -> Control:
	var row := Label.new()
	var label: String = in_recipe.label
	if label == "":
		label = in_recipe.output if in_recipe.output != "" else "(empty recipe)"
	row.text = label
	return row

# —— 拖放 target(_building 为唯一接收建筑)——

# 接受拖放:数据是带 drag_recipe_index 的字典(来自 WorkshopRecipeRow._get_drag_data)。
func _can_drop_data(_in_position: Vector2, in_data: Variant) -> bool:
	return in_data is Dictionary and in_data.has("drag_recipe_index")

# 接收 drop:由落点 Y 推断目标索引,emit recipe_dropped(from, to)。
func _drop_data(at_position: Vector2, in_data: Variant):
	if not (in_data is Dictionary):
		return
	var drag_dict: Dictionary = in_data
	var from_index: int = drag_dict.get("drag_recipe_index", -1)
	var to_index: int = _index_at_position(at_position)
	if to_index < 0 or to_index == from_index:
		return
	recipe_dropped.emit(from_index, to_index)

# 由 drop 屏幕位置(相对本容器)推断插入目标行索引(VBox 按子项 Y 中心分桶)。
func _index_at_position(in_local_position: Vector2) -> int:
	if get_child_count() == 0:
		return -1
	for i in get_child_count():
		var child: Control = get_child(i) as Control
		if not child:
			continue
		var center_y: float = child.position.y + child.size.y * 0.5
		if in_local_position.y < center_y:
			return i
	return get_child_count() - 1
