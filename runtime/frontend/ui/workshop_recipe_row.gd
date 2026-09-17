class_name WorkshopRecipeRow
extends PanelContainer

# 配方行:单张配方的展示与拖拽源。布局(参考 Satisfactory 高炉配方卡):
#   Header  — 名称行:Handle(自绘六点抓手,拖拽提示)+ Name(配方名 RecipeData.label)
#   Items   — 原料/产物控件横排:每个物料一"竖条(库存占比)+数量",之间用 + / -> / 耗时⏱ 分隔
#   Progress— 当前执行进度横条(仅 active 配方实时,其余空)
# 拖拽源协议:_get_drag_data 返回带 drag_recipe_index/grab_offset_y 的字典并发 drag_started,
# 由 WorkshopRecipeList 接管视觉(行跟随指针、其余行让位、松手滑入空档)。不设 drag preview ——
# 跟随指针的就是行本身;行在列表内的位置由列表按槽位显式摆放(列表不是容器)。
# setup(recipe, index, building, is_active) 由列表填充。
#
# 行是哑组件:只展示 + 提供拖拽数据,不直接调 backend 改状态(move_recipe 由面板经 list)。
# 触屏无悬停、内置拖放对触摸不可靠,故 Header 另提供 ▲/▼ 按钮,经 move_requested 上报。

signal move_requested(from_index: int, to_index: int)
# 本行开始被拖拽(from_index, 指针在行内的抓取偏移 Y):列表据此接管跟随/让位/落位
signal drag_started(from_index: int, grab_offset_y: float)

# 未执行配方的进度条填充色(灰),与执行中的工作量黄区分
const COLOR_PENDING: Color = Color(0.3, 0.3, 0.3, 0.5)

var _recipe: RecipeData = null
var recipe_index: int = -1
var _building: Workshop = null
var _is_active: bool = false

# 每个物料项包含的控件引用(竖条 + 数量),供每帧刷新库存占比
var _item_bars: Array = []   # 每个元素: { "bar": ProgressBar, "type": String, "num": Label }
var _time_label: Label = null  # 耗时文本(箭头下方)
var _progress_fill: StyleBoxFlat = null  # 本行私有的进度条填充样式(见 _ensure_progress_fill)

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
	# 行保持 PASS:Viewport::_gui_drop 从指针下的控件向上找拖放目标时,遇到
	# "can_drop_data 为假且 mouse_filter = STOP"的控件就 break。本行不实现 _can_drop_data
	# (拖放目标是父级 RecipeList),若此处为 STOP,拖放永远到不了列表;PASS 让事件继续上溯。
	mouse_filter = Control.MOUSE_FILTER_PASS

# 节点每次现查(不 reliance _ready 顺序):setup 可能在 _ready 前被调用,
# 缓存引用会拿到 null 导致 Items 区空白。
func _items() -> HBoxContainer:
	return get_node_or_null("Layout/Items") as HBoxContainer

# 抓手是纯装饰:必须 IGNORE,否则 Viewport::_gui_drop 上溯到它时 break(见 make_draggable)
func _handle() -> Control:
	return get_node_or_null("Layout/Header/Handle") as Control

# 抓手圆点由代码绘制而非字形:默认主题字体(Open Sans)不含 ⠿ 等盲文/点阵字形,
# 直接写字形会渲染成缺字方块;自绘圆点才能保证任何字体环境下都清晰可读。
func _ready():
	var handle := _handle()
	if handle and not handle.draw.is_connected(_draw_handle):
		handle.draw.connect(_draw_handle)
		# 绘制指令存于局部坐标,尺寸变化不会自动重算圆点位置,需主动重画
		if not handle.resized.is_connected(handle.queue_redraw):
			handle.resized.connect(handle.queue_redraw)
	var move_up := get_node_or_null("Layout/Header/MoveUp") as Button
	if move_up and not move_up.pressed.is_connected(_on_move_up_pressed):
		move_up.pressed.connect(_on_move_up_pressed)
	var move_down := get_node_or_null("Layout/Header/MoveDown") as Button
	if move_down and not move_down.pressed.is_connected(_on_move_down_pressed):
		move_down.pressed.connect(_on_move_down_pressed)

func _on_move_up_pressed():
	move_requested.emit(recipe_index, recipe_index - 1)

func _on_move_down_pressed():
	move_requested.emit(recipe_index, recipe_index + 1)

# 2 列 × 3 行六点抓手(标准拖拽把手样式);用次要用色,不与配方名抢眼
func _draw_handle():
	var handle := _handle()
	if not handle:
		return
	var spacing: Vector2 = Vector2(5.0, 5.0)
	var origin: Vector2 = handle.size * 0.5 - Vector2(spacing.x * 0.5, spacing.y)
	for row: int in 3:
		for col: int in 2:
			var center: Vector2 = origin + Vector2(float(col) * spacing.x, float(row) * spacing.y)
			handle.draw_circle(center, 1.5, Color(0.6, 0.68, 0.8, 0.9), true, -1.0, true)

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
	var name_node: Label = get_node_or_null("Layout/Header/Name") as Label
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
	# 显示用竖条必须 IGNORE:Control 默认 mouse_filter = STOP,而 Viewport::_gui_drop 向上找
	# 拖放目标时遇到 STOP 就 break(详见 make_draggable 注释)。否则拖到这根竖条上放不下来。
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(8, 44)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	bar.add_theme_stylebox_override("background", _make_style(Color(0, 0, 0, 0.4)))
	# 物料竖条 = 该物料的库存/容量占比,与建筑头顶容量条同色
	bar.add_theme_stylebox_override("fill", _make_style(BuildingCapacityBar.COLOR_CAPACITY))
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

# 本行私有的进度条填充样式:场景里的 SubResource 被所有行共享,直接改色会互相覆盖,
# 故首次使用时复制一份(保留圆角)并作为本行 override。
func _ensure_progress_fill(in_bar: ProgressBar) -> StyleBoxFlat:
	if _progress_fill:
		return _progress_fill
	var base := in_bar.get_theme_stylebox("fill")
	if base is StyleBoxFlat:
		_progress_fill = (base as StyleBoxFlat).duplicate(true) as StyleBoxFlat
	else:
		_progress_fill = _make_style(WorkProgressBar.COLOR_WORK)
	in_bar.add_theme_stylebox_override("fill", _progress_fill)
	return _progress_fill

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
	# 执行中的配方用工作量条黄(与建筑头顶 WorkProgressBar 同色),未执行的行留灰
	var fill := _ensure_progress_fill(_progress_bar)
	fill.bg_color = WorkProgressBar.COLOR_WORK if _is_active else COLOR_PENDING
	# 进度说明文字(旁边写明):仅当前执行的配方显示百分比,其余显示 Pending
	var label := _progress_label()
	if label:
		if _is_active:
			label.text = "%d%%" % int(round(ratio * 100.0))
		else:
			label.text = "Pending"

# —— 拖拽源 ——

# 拖拽源:返回索引 + 抓取偏移(指针在行内的 Y),并发 drag_started 让列表接管视觉。
# 不调用 set_drag_preview:跟随指针的是行本身(列表按指针 Y 摆放它),不需要浮层预览。
func _get_drag_data(in_at_position: Vector2):
	var drag_recipe_index: int = get_meta(&"drag_recipe_index", -1)
	if drag_recipe_index < 0 or _recipe == null:
		return null
	var drag_data: Dictionary = {
		"drag_recipe_index": drag_recipe_index,
		"grab_offset_y": in_at_position.y,
	}
	drag_started.emit(drag_recipe_index, in_at_position.y)
	return drag_data
