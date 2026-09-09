class_name WorkshopRecipeRow
extends PanelContainer

# 配方行:单张配方的展示与拖拽源。布局(参考 Satisfactory 高炉配方卡):
#   Name    — 配方名(RecipeData.label)
#   Items   — 原料/产物控件横排:每个物料一"竖条(库存占比)+数量",之间用 + / -> / 耗时⏱ 分隔
#   Progress— 当前执行进度横条(仅 active 配方实时,其余空)
# 拖拽源协议:_get_drag_data 返回带 drag_recipe_index 的字典,由 WorkshopRecipeList._drop_data
# 接收并换算目标行。setup(recipe, index, building, is_active) 由列表容器填充。
#
# 行是哑组件:只展示 + 提供拖拽数据,不直接调 backend 改状态(move_recipe 由面板经 list)。

var _recipe: RecipeData = null
var recipe_index: int = -1
var _building: Workshop = null
var _is_active: bool = false

# 每个物料项包含的控件引用(竖条 + 数量),供每帧刷新库存占比
var _item_bars: Array = []   # 每个元素: { "bar": ProgressBar, "type": String, "num": Label }
var _time_label: Label = null  # 耗时文本(箭头下方)

func setup(in_recipe: RecipeData, in_index: int, in_building: Workshop,
		in_is_active: bool = false):
	_recipe = in_recipe
	recipe_index = in_index
	_building = in_building
	_is_active = in_is_active
	_refresh_visual()
	_build_items()
	_refresh_progress()

func make_draggable():
	set_meta(&"drag_recipe_index", recipe_index)

# 节点每次现查(不 reliance _ready 顺序):setup 可能在 _ready 前被调用,
# 缓存引用会拿到 null 导致 Items 区空白。
func _items() -> HBoxContainer:
	return get_node_or_null("Layout/Items") as HBoxContainer

func _progress() -> ProgressBar:
	return get_node_or_null("Layout/ProgressRow/Progress") as ProgressBar

func _progress_label() -> Label:
	return get_node_or_null("Layout/ProgressRow/ProgressLabel") as Label

func _process(_in_delta: float):
	if not _building:
		return
	if _is_active and _progress():
		_refresh_progress()
	_refresh_items()

# —— 配方名/背景 ——

func _refresh_visual():
	var name_node: Label = get_node_or_null("Layout/Name") as Label
	if name_node:
		name_node.text = _recipe.label if _recipe and _recipe.label != "" else "(empty)"
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.35, 0.5, 0.95, 0.35) if _is_active else Color(0.2, 0.2, 0.2, 0.25)
	panel_style.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", panel_style)

# —— 物料控件横排(重建) ——

# 程序化构建 Items 横排:每个物料一竖条+数量,中间 + / -> / 耗时⏱ 分隔。
func _build_items():
	var _items_box := _items()
	if not _items_box:
		return
	_clear_items()
	if not _recipe:
		return
	# 输入侧
	var added_input: bool = false
	for input: RecipeInputData in _recipe.inputs:
		if added_input:
			_add_separator("+")
		_add_item(input.item_type, input.count)
		added_input = true
	# 无输入但无输出:留空(不显示 (none))
	# 箭头 + 耗时(仅当有输出)
	if _recipe.output == "":
		return
	_add_arrow_with_time(_recipe.workload_per_unit)
	# 输出侧
	_add_item(_recipe.output, _recipe.output_count)

func _clear_items():
	var _items_box := _items()
	if not _items_box:
		return
	for child in _items_box.get_children():
		_items_box.remove_child(child)
		child.queue_free()
	_item_bars.clear()
	_time_label = null

# 一个物料项:竖条(库存占比,下→上填充)+ 名称 + 数量。记录控件引用供每帧刷新。
# 结构(参考图 a=容量条/bb=名称/cc=数量 三层):
#   HBox{ VBox{竖条(窄高)}, VBox{Label名称, Label数量} }
func _add_item(in_item_type: String, in_num: int):
	var item := HBoxContainer.new()
	item.custom_minimum_size = Vector2(0, 56)
	item.add_theme_constant_override("separation", 4)
	# 竖条列(容量条 a):窄高 ProgressBar,FILL_BOTTOM_TO_TOP,居中
	var bar_col := VBoxContainer.new()
	bar_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(8, 44)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	bar.add_theme_stylebox_override("background", _make_style(Color(0, 0, 0, 0.4)))
	bar.add_theme_stylebox_override("fill", _make_style(Color(0.4, 0.8, 0.95, 0.9)))
	bar_col.add_child(bar)
	item.add_child(bar_col)
	# 名称 + 数量列(bb / cc):垂直居中,与竖条中部对齐
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 0)
	var name_lbl := Label.new()
	name_lbl.text = in_item_type
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98, 1))
	info.add_child(name_lbl)
	var num := Label.new()
	num.text = str(in_num)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	num.add_theme_font_size_override("font_size", 11)
	num.add_theme_color_override("font_color", Color(0.6, 0.68, 0.8, 1))
	info.add_child(num)
	item.add_child(info)
	_items().add_child(item)
	_item_bars.append({ "bar": bar, "type": in_item_type, "num": num, "item": item })

func _add_separator(in_text: String):
	_add_text(in_text)

func _add_text(in_text: String):
	var lbl := Label.new()
	lbl.text = in_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9, 1))
	_items().add_child(lbl)

# 箭头 + 下方耗时:一个 VBox(箭头 "→" + 耗时 "60⏱")。
func _add_arrow_with_time(in_workload: float):
	var arrow := VBoxContainer.new()
	arrow.alignment = BoxContainer.ALIGNMENT_CENTER
	arrow.add_theme_constant_override("separation", 0)
	var a := Label.new()
	a.text = "→"
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.add_theme_font_size_override("font_size", 14)
	a.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98, 1))
	arrow.add_child(a)
	var t := Label.new()
	t.text = "%d⏱" % int(round(in_workload))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 10)
	t.add_theme_color_override("font_color", Color(0.6, 0.68, 0.8, 1))
	arrow.add_child(t)
	_items().add_child(arrow)
	_time_label = t

func _make_style(in_color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = in_color
	s.set_corner_radius_all(2)
	return s

# —— 每帧刷新物料竖条与数量 ——

func _refresh_items():
	for entry: Dictionary in _item_bars:
		var bar: ProgressBar = entry["bar"]
		var item_type: String = entry["type"]
		bar.max_value = 100.0
		var cap: int = _building.get_capacity(item_type) if _building else 0
		var stock: int = _building.get_stock(item_type) if _building else 0
		var fill_ratio: float = (float(stock) / float(cap)) if cap > 0 else 0.0
		bar.value = clampf(fill_ratio, 0.0, 1.0) * 100.0

# —— 进度横条 ——

func _refresh_progress():
	var _progress_bar := _progress()
	if not _progress_bar:
		return
	var ratio: float = 0.0
	if _is_active and _building:
		ratio = clampf(_building.progress, 0.0, 1.0)
	_progress_bar.value = ratio * 100.0
	var fill: StyleBoxFlat = _progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill == null:
		fill = _make_style(Color(0.35, 0.85, 0.95, 0.9))
		_progress_bar.add_theme_stylebox_override("fill", fill)
	fill.bg_color = Color(0.35, 0.85, 0.95, 0.9) if _is_active else Color(0.3, 0.3, 0.3, 0.5)
	# 进度说明文字(旁边写明):仅当前执行的配方显示百分比,其余显示 Pending
	var label := _progress_label()
	if label:
		if _is_active:
			label.text = "%d%%" % int(round(ratio * 100.0))
		else:
			label.text = "Pending"

# —— 拖拽源 ——

func _get_drag_data(_in_at_position: Vector2):
	var drag_recipe_index: int = get_meta(&"drag_recipe_index", -1)
	if drag_recipe_index < 0 or _recipe == null:
		return null
	var drag_data: Dictionary = { "drag_recipe_index": drag_recipe_index }
	set_drag_preview(_make_preview())
	return drag_data

func _make_preview() -> Control:
	var preview := Label.new()
	preview.text = _recipe.label if _recipe and _recipe.label != "" else _recipe.output
	preview.modulate = Color(0.9, 0.9, 0.9, 0.8)
	preview.custom_minimum_size = Vector2(120, 24)
	return preview
