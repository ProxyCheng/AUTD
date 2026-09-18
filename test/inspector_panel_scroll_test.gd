extends SceneTree

# 检视面板滚动回归测试:内容过高时必须能滚,而不是溢出面板。
#
# 回归背景:面板 %Components 原先直接铺在面板里,可用高度只有 480 − 44(标题) − 64(删除按钮)
# = 372px;一个作坊要放 Priority + StorageContent + RecipeList,而配方行 custom_minimum_size
# 就有 96px —— 工具坊三条配方实测内容高 396px,超出 24px,第三行被删除按钮压住。
#
# 修法两条,本测试各钉一条:
#   1. 把 %Components 套进一个只竖滚的 ScrollContainer —— 结构契约(七个组件仍直接挂在
#      %Components 下,%Components 的父节点是竖向滚动容器,横向滚动禁用);
#   2. 让 WorkshopRecipeList 上报内容高度(它自己显式摆行,Control 默认最小高度为 0,
#      外层 ScrollContainer 否则量不到滚动范围)—— 行为契约(内容装不下时滚动范围真的覆盖全部行)。
#
# 面板必须**可见**才有布局(隐藏的 Control 不重排,滚动范围会停在旧值),故先 show 再 populate,
# 与真实流程一致(检视时 configure → show → 绑组件)。
#
#   <godot.exe> --path <项目根> --headless --script res://test/inspector_panel_scroll_test.gd
#
# 退出码 = 失败项数(0 = 全过)。

const PANEL_PATH: String = "res://runtime/frontend/ui/building_inspector_panel.tscn"
# 配方行的声明最小高度(见 workshop_recipe_row.tscn 的 custom_minimum_size)
const ROW_MIN_HEIGHT: float = 96.0
# 用来把内容撑到必然溢出的配方条数(视口只有 372px 高)
const OVERFLOW_RECIPES: int = 8

func _init():
	_run()

func _make_recipe(in_label: String) -> RecipeData:
	var recipe := RecipeData.new()
	recipe.label = in_label
	recipe.output = "log"
	return recipe

func _run() -> void:
	var failed: int = 0

	var panel: Control = (load(PANEL_PATH) as PackedScene).instantiate()
	root.add_child(panel)
	# 先让 _ready 跑完(它会把面板 hide 掉),之后再 show —— 否则 show 会被随后的 _ready 覆盖
	await process_frame

	# —— 1. 结构契约:七个组件仍直接挂在 %Components 下,且 %Components 位于只竖滚的滚动容器内 ——
	var components: Control = panel.get_node_or_null("%Components")
	if components == null:
		print("CASE components_present false  expect=true")
		quit(1)
		return
	var names: Array = []
	for child in components.get_children():
		names.append(child.name)
	print("CASE components_present children=", names)
	if names.size() != 7:
		failed += 1
	var scroll: Node = components.get_parent()
	print("CASE scroll_wraps_components ", scroll is ScrollContainer)
	if not (scroll is ScrollContainer):
		failed += 1
	else:
		print("CASE horizontal_scroll_disabled ", scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
		if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			failed += 1

	# —— 2. 行为契约:内容装不下时,列表上报内容高度、滚动范围覆盖全部行 ——
	panel.show()
	await process_frame
	var list: Control = components.get_node("RecipeList/RecipeList")
	var workshop := Workshop.new()
	for i in OVERFLOW_RECIPES:
		workshop.recipes.append(_make_recipe("R%d" % i))
	list.populate(workshop)
	await process_frame
	await process_frame
	var min_size: Vector2 = list.get_combined_minimum_size()
	var bar: VScrollBar = (scroll as ScrollContainer).get_v_scroll_bar()
	var viewport_h: float = (scroll as ScrollContainer).size.y
	print("CASE list_reports_height ", min_size,
		" expect>= (0, ", OVERFLOW_RECIPES * ROW_MIN_HEIGHT, ")")
	if min_size.y < OVERFLOW_RECIPES * ROW_MIN_HEIGHT:
		failed += 1
	print("CASE scroll_range viewport_h=", viewport_h, " content_h=", bar.max_value,
		" vbar_visible=", bar.visible, " expect content>=", OVERFLOW_RECIPES * ROW_MIN_HEIGHT)
	if bar.max_value < OVERFLOW_RECIPES * ROW_MIN_HEIGHT or not bar.visible:
		failed += 1

	# —— 3. 清空后列表重新归零,不留旧的滚动范围 ——
	list.clear()
	await process_frame
	var cleared: Vector2 = list.get_combined_minimum_size()
	print("CASE cleared_min_size ", cleared, " expect=(0, 0)")
	if cleared != Vector2.ZERO:
		failed += 1

	workshop.free()
	panel.free()

	print("RESULT failed=", failed)
	quit(failed)
