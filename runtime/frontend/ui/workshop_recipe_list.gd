class_name WorkshopRecipeList
extends Control

# 作坊面板的配方列表:渲染每张配方(WorkshopRecipeRow)、自管槽位布局,并作为拖放目标。
#
# 布局:本控件是纯 Control(非容器)—— 容器会接管子项位置,被拖的行无法跟随指针、
# 其它行也无法让位。行的位置/尺寸全部由这里显式摆放:
#   槽位 i 的 top = i * (行高 + ROW_GAP);行高取行的内容最小高度(≥ ROW_HEIGHT,见 _apply_row_height)。
#
# 拖拽(拖拽源在行上,见 workshop_recipe_row):
#   1. 行 _get_drag_data 返回 drag_recipe_index/grab_offset_y 并发 drag_started → 本控件接管;
#   2. 拖拽期间每帧把被拖行摆到"指针 Y - 抓取偏移"(夹在列表矩形内,画在最上层),
#      目标槽位变化时把其余行补间到让位槽位,在目标处空出一格(目标不变则不重建补间);
#   3. 松手落在列表内:原生拖放回调 _drop_data,被拖行滑进空档,滑完 emit recipe_dropped,
#      面板据此调 Workshop.move_recipe —— backend recipes 是唯一顺序真相,本控件不存本地顺序;
#   4. 松手在列表外 / ESC:原生拖放取消(不回调 _drop_data),本控件在 _process 察觉拖拽
#      结束且未落库,把行补间回原槽位,不发信号。
#
# 重建时机:面板 _refresh 会整表重建(populate),而拖拽中重建会释放正在被拖的行。
# 故面板在 is_dragging() 期间推迟刷新,等拖拽/落位动画彻底结束(本控件发 drag_finished)后补刷。

signal recipe_dropped(from_index: int, to_index: int)
# 与列表的交互(按住行 / 拖拽 + 落位/回位动画)彻底结束:面板用于补做期间被推迟的刷新。
signal drag_finished()

const ROW_SCENE_PATH: String = "res://runtime/frontend/ui/workshop_recipe_row.tscn"
# 行高下限(写入行 custom_minimum_size 的声明值);实际行高由行内容决定,见 _apply_row_height
const ROW_HEIGHT: float = 64.0
# 相邻行之间的空档:槽位间距 = ROW_HEIGHT + ROW_GAP
const ROW_GAP: float = 4.0
# 让位补间时长(其余行随目标槽位滑动)
const SHIFT_DURATION: float = 0.12
# 落位/回位补间时长(被拖行滑进空档 / 滑回原位)
const SETTLE_DURATION: float = 0.14

var _building: Workshop = null
# 配方索引 → 行 的显式映射(顺序与 recipes 一致)。拖拽会把被拖行 move_child 到最上层,
# 故索引换算不能依赖子节点次序。
var _rows: Array[Control] = []
# 实际行高:行内容(名称/物料/进度)的最小高度,通常大于 ROW_HEIGHT 的声明值。
# 槽位公式要求所有行等高,populate 时统一(见 _apply_row_height)。
var _row_height: float = ROW_HEIGHT

# —— 拖拽状态 ——
var _drag_row: Control = null       # 被拖行;非 null = 拖拽进行中(含落位/回位动画)
var _drag_from: int = -1            # 被拖行的原始配方索引
var _drag_target: int = -1          # 当前目标槽位(= 松手后的最终索引,见 _target_slot_at)
var _drag_grab_offset: float = 0.0  # 按下点相对行顶的偏移:拖拽时保持"抓住"行的同一位置
var _settling: bool = false         # 落位/回位补间进行中
var _drop_pending: bool = false     # 落位补间进行中且 recipe_dropped 尚未发出
var _settle_tween: Tween = null     # 落位/回位补间(终结拖拽时显式 kill)
var _row_tweens: Dictionary = {}    # { Control: Tween } 让位补间(重定目标时先 kill 旧补间)
# 指针位置(视口坐标)与有效性:跟随以输入事件为准,见 _input
var _pointer_position: Vector2 = Vector2.ZERO
var _has_pointer: bool = false
# 左键已按在行上、拖拽尚未开始:期间同样要阻止面板重建 ——
# 重建会释放按下的行,Viewport 随即清掉 mouse_focus(见 _gui_remove_control),
# 拖拽就永远起不来(active_recipe_changed 的高频重建会稳定复现)。
var _press_armed: bool = false
# 按住刚松开:交互结束通知延到 _process 再发(见 _process 注释)
var _press_released: bool = false

func _ready():
	# 列表矩形变化(面板尺寸)时重摆行:行位置由本控件管理,不会自动跟随
	resized.connect(_layout_rows)

# 记录指针位置与按住状态:拖拽的 motion 事件只经 _input/GUI 派发,而根视口的
# Viewport.get_mouse_position() 取的是 OS 光标(窗口失焦或注入事件时不可靠),故跟随一律用事件位置。
# _input 先于 GUI 处理,拖拽起始那一下 motion 也已被记录。
func _input(in_event: InputEvent):
	if not is_visible_in_tree():
		return
	var motion: InputEventMouseMotion = in_event as InputEventMouseMotion
	if motion:
		_pointer_position = motion.position
		_has_pointer = true
		return
	var button: InputEventMouseButton = in_event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	# 按下/松手都记录位置:松手位置是落点判定的权威来源(见 _can_drop_data/_drop_data)
	_pointer_position = button.position
	_has_pointer = true
	if button.pressed:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * button.position
		_press_armed = _row_at_local(local) != null
	elif _press_armed:
		_press_armed = false
		# 松手通知延到 _process 发:此刻 GUI 还没把这次松手交给按下的控件
		# (▲/▼ 按钮靠松手触发 pressed),在这里触发重建会把按钮提前销毁、点击丢失。
		_press_released = true

# 渲染某建筑的全部配方(每次全量重排,保证与 backend recipes 顺序一致)。
func populate(in_building: Workshop):
	_abort_drag()
	_building = in_building
	_clear_rows()
	if not _building:
		return
	var row_index: int = 0
	for recipe: RecipeData in _building.recipes:
		_append_row(recipe, row_index)
		row_index += 1
	_apply_row_height()
	_layout_rows()

# 公开清空:移除全部配方行并重置 building 引用。
# 关闭面板/解绑时调用,避免行 _process 在建筑被释放后仍访问已失效 _building(freed instance)。
func clear():
	_abort_drag()
	# 面板关闭时鼠标可能仍按着:一并解除按住态,否则重开后 is_dragging 会一直为真、刷新被永久推迟
	_press_armed = false
	_press_released = false
	_building = null
	_clear_rows()

# 拖拽(含落位/回位动画)是否进行中:面板据此推迟重建,避免释放正在被拖的行。
# 按住(尚未拖起来)也算:见 _press_armed。
func is_dragging() -> bool:
	return _drag_row != null or _press_armed

func _clear_rows():
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_rows.clear()
	_kill_row_tweens()

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
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	# 行内 ▲/▼ 按钮(触屏可用)与拖放共用同一条落库路径。
	if row.has_signal(&"move_requested"):
		row.connect(&"move_requested", _on_row_move_requested)
	# 行开始拖拽 → 本控件接管跟随/让位/落位
	if row.has_signal(&"drag_started"):
		row.connect(&"drag_started", _on_row_drag_started)
	_rows.append(row)

func _make_fallback_row(in_recipe: RecipeData) -> Control:
	var row := Label.new()
	var label: String = in_recipe.label
	if label == "":
		label = in_recipe.output if in_recipe.output != "" else "(empty recipe)"
	row.text = label
	return row

# —— 槽位布局(替代容器布局)——

# 统一实际行高:取各行内容最小高度(custom_minimum_size 只是下限,行内容更高),
# 并写回 custom_minimum_size 让所有行等高 —— 槽位公式要求等高。
func _apply_row_height():
	var tallest: float = ROW_HEIGHT
	for row: Control in _rows:
		tallest = maxf(tallest, row.get_combined_minimum_size().y)
	_row_height = tallest
	for row: Control in _rows:
		row.custom_minimum_size = Vector2(0, _row_height)

func _slot_height() -> float:
	return _row_height + ROW_GAP

func _slot_y(in_slot: int) -> float:
	return float(in_slot) * _slot_height()

# 被拖行可移动的最大 top:夹在列表矩形内(行高固定)
func _max_row_top() -> float:
	return maxf(0.0, size.y - _row_height)

# 摆放全部行:静止时回到各自槽位;拖拽中只同步尺寸(位置归拖拽逻辑管)。
func _layout_rows():
	for i in _rows.size():
		var row: Control = _rows[i]
		row.size = Vector2(size.x, _row_height)
		if _drag_row == null:
			row.position = Vector2(0.0, _slot_y(i))

# 命中测试(列表局部坐标 → 行):仅用于判断按下是否落在某一行上(此时行都在静止槽位)
func _row_at_local(in_local: Vector2) -> Control:
	for i in _rows.size():
		if in_local.y >= _slot_y(i) and in_local.y < _slot_y(i) + _row_height:
			return _rows[i]
	return null

# —— 拖拽:视觉接管(拖拽源协议见 workshop_recipe_row)——

func _on_row_drag_started(in_from_index: int, in_grab_offset: float):
	# 落位/回位动画(0.14s)未完时的第二次拖拽:先补发上一次结果,本次忽略 ——
	# 动画中途整表重建比"忽略一次拖拽"危险得多,而重入窗口极小。
	if _drag_row:
		_abort_drag()
		return
	if in_from_index < 0 or in_from_index >= _rows.size():
		return
	_drag_row = _rows[in_from_index]
	_drag_from = in_from_index
	_drag_target = in_from_index
	_drag_grab_offset = in_grab_offset
	_settling = false
	_drop_pending = false
	# 被拖行画在最上层:让位动画中它始终浮在其它行之上
	move_child(_drag_row, get_child_count() - 1)

func _process(_in_delta: float):
	# 按住刚松开且没变成拖拽(单击/长按):补发一次交互结束,让面板补做推迟的刷新。
	# 必须等到这里 —— 输入事件在 _process 之前派发完毕,▲/▼ 按钮的 pressed 已经触发,
	# 此时重建才不会吞掉这次点击。若正在拖拽,松手由 _drop_data/_cancel_drag 收尾,不重复发。
	if _press_released:
		_press_released = false
		if _drag_row == null:
			drag_finished.emit()
	if _drag_row == null or _settling:
		return
	if not is_instance_valid(_drag_row):
		_reset_drag_state()
		_kill_row_tweens()
		return
	var viewport: Viewport = get_viewport()
	if viewport and viewport.gui_is_dragging():
		_update_drag()
	else:
		# 原生拖放已结束却没走 _drop_data:松手在列表外或 ESC 取消 → 回原位,不发信号
		_cancel_drag()

# 每帧:被拖行跟随指针(夹在列表矩形内);目标槽位变化时让位补间。
func _update_drag():
	var pointer_y: float = _pointer_local().y
	_drag_row.position.y = clampf(pointer_y - _drag_grab_offset, 0.0, _max_row_top())
	var target: int = _target_slot_at(pointer_y)
	if target == _drag_target:
		return
	_drag_target = target
	_shift_rows_to_gap()

# 指针在列表局部坐标下的位置(拖拽跟随与目标槽位的唯一输入);
# 未记录到任何 motion 时退回 Viewport 光标位置(正常流程不会走到)。
func _pointer_local() -> Vector2:
	if not _has_pointer:
		return get_local_mouse_position()
	return get_global_transform_with_canvas().affine_inverse() * _pointer_position

# 指针 Y → 目标槽位(0..行数-1):取"被拖行中心"最近的静止槽位中心。
# 槽位中心 = 槽位顶 + 行高/2,行中心 = 行 top + 行高/2,故等价于对行 top 做最近邻取整;
# 行中心越过两槽位中心的中点(即拖动约半格)才换目标 —— 边界有回滞,不会来回抖。
# 两端 clamp 到首/末槽:拖到列表顶部以上落 0 号槽,拖到底部落末槽。
#
# 目标槽位 == move_recipe 的 to:backend 是"先移除再插入"(remove_at → insert),
# 行从 from 移走后其余行恰好挪一格,被拖行落进的槽位就是它在新数组中的索引。
# 例:[A,B,C] 把 A 拖到槽 1 → 移除 A 得 [B,C],insert(1) → [B,A,C];把 B 拖到槽 0 → [B,A,C]。
# 即"下移一格"与"上移一格"的最终索引都等于目标槽位。
func _target_slot_at(in_pointer_y: float) -> int:
	var count: int = _rows.size()
	if count <= 0:
		return -1
	var top: float = clampf(in_pointer_y - _drag_grab_offset, 0.0, _max_row_top())
	var nearest: int = int(round(top / _slot_height()))
	return clampi(nearest, 0, count - 1)

# 让位:目标在下方时 (from, target] 的行上移一格;目标在上方时 [target, from) 的行下移一格;
# 其余行不动 —— 空档恰好出现在目标槽位。
func _shift_rows_to_gap():
	for i in _rows.size():
		var row: Control = _rows[i]
		if row == _drag_row:
			continue
		_tween_row_to(row, _slot_y(_display_slot(i)))

func _display_slot(in_index: int) -> int:
	if _drag_from < _drag_target and in_index > _drag_from and in_index <= _drag_target:
		return in_index - 1
	if _drag_from > _drag_target and in_index >= _drag_target and in_index < _drag_from:
		return in_index + 1
	return in_index

# 行位移补间:同一行重定目标时先 kill 旧补间,避免两条补间抢同一属性
func _tween_row_to(in_row: Control, in_y: float):
	var previous: Tween = _row_tweens.get(in_row) as Tween
	if previous and previous.is_valid():
		previous.kill()
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(in_row, "position:y", in_y, SHIFT_DURATION)
	_row_tweens[in_row] = tween

func _kill_row_tweens():
	for tween: Tween in _row_tweens.values():
		if tween and tween.is_valid():
			tween.kill()
	_row_tweens.clear()

# —— 拖放 target(_building 为唯一接收建筑)——

# 接受拖放:数据是带 drag_recipe_index 的字典(来自 WorkshopRecipeRow._get_drag_data),
# 且当前指针必须落在列表矩形内。位置以本控件跟踪的事件位置为准而非 Godot 传入的 at_position:
# 原生拖放在"光标移出窗口"时不再更新 drag_mouse_over,传入的会是陈旧控件的外推坐标;
# 用事件位置还能保证"松手落点"与"拖拽时看到的空档"完全一致(同一来源)。
func _can_drop_data(_in_position: Vector2, in_data: Variant) -> bool:
	if _drag_row == null or not (in_data is Dictionary) or not in_data.has("drag_recipe_index"):
		return false
	return Rect2(Vector2.ZERO, size).has_point(_pointer_local())

# 接收 drop(松手在列表内):把被拖行滑进目标槽位。
func _drop_data(_in_at_position: Vector2, in_data: Variant):
	if _drag_row == null or _settling or not (in_data is Dictionary):
		return
	var drag_dict: Dictionary = in_data
	var from_index: int = int(drag_dict.get("drag_recipe_index", -1))
	if from_index != _drag_from:
		return
	var target: int = _target_slot_at(_pointer_local().y)
	if target == _drag_from:
		_cancel_drag()
		return
	_drag_target = target
	_settle_into_slot()

# 落位:被拖行滑进空档,滑完才 emit recipe_dropped ——
# 面板收到后会 move_recipe → recipe_order_changed → 整表重建(populate),
# 必须等滑行结束,否则正在滑的行会在半途被释放。
func _settle_into_slot():
	_settling = true
	_drop_pending = true
	_settle_tween = create_tween()
	_settle_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_settle_tween.tween_property(_drag_row, "position:y", _slot_y(_drag_target), SETTLE_DURATION)
	_settle_tween.finished.connect(_on_settle_finished)

func _on_settle_finished():
	var from_index: int = _drag_from
	var to_index: int = _drag_target
	_reset_drag_state()
	if from_index >= 0 and to_index >= 0 and from_index != to_index:
		recipe_dropped.emit(from_index, to_index)
	# 面板通常已在 recipe_dropped 回调里重建;若未重建(无 building),把让位的行摆回静止槽位
	_layout_rows()
	drag_finished.emit()

# 取消(松手在列表外 / ESC):被拖行滑回原槽位,不发 recipe_dropped。
func _cancel_drag():
	_settling = true
	_drop_pending = false
	_settle_tween = create_tween()
	_settle_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_settle_tween.tween_property(_drag_row, "position:y", _slot_y(_drag_from), SETTLE_DURATION)
	_settle_tween.finished.connect(_on_cancel_finished)

func _on_cancel_finished():
	_reset_drag_state()
	# 让位的行补间回静止槽位
	for i in _rows.size():
		_tween_row_to(_rows[i], _slot_y(i))
	drag_finished.emit()

func _reset_drag_state():
	_drag_row = null
	_drag_from = -1
	_drag_target = -1
	_drag_grab_offset = 0.0
	_settling = false
	_drop_pending = false
	_settle_tween = null

# 强制终结进行中的拖拽(重建/清空前调用)。若落位动画被打断,补发 recipe_dropped:
# 用户已经松手并看到落位,排序不能因为面板关闭或重建而丢失。
func _abort_drag():
	if _drag_row == null:
		return
	var pending_from: int = _drag_from
	var pending_target: int = _drag_target
	var had_drop: bool = _drop_pending
	if _settle_tween and _settle_tween.is_valid():
		_settle_tween.kill()
	_reset_drag_state()
	_kill_row_tweens()
	if had_drop and pending_from >= 0 and pending_target >= 0 and pending_from != pending_target:
		recipe_dropped.emit(pending_from, pending_target)

# 行内 ▲/▼ 按钮上报相邻移动:换算为 drop 语义并广播(与拖放共用落库路径)。
func _on_row_move_requested(in_from_index: int, in_to_index: int):
	if in_to_index < 0 or in_to_index >= _rows.size():
		return
	recipe_dropped.emit(in_from_index, in_to_index)
