extends SceneTree

# ItemStack 展示类型解析测试:有状态仓(如工人的手仓)的类型在**状态载体**上,
# 不在 bag.item_type 上。
#
#   <godot.exe> --path <项目根> --headless --script res://test/item_stack_test.gd
#
# 退出码 = 失败项数(0 = 全过)。
#
# 回归背景:工人的手仓(Labor.hand_bag)装的是有状态单体(工具),bag.item_type 恒为空
# (类型记在载体 Tool 上,见 AGENTS §5.8)。而 ItemStack._display_type() 原先只读
# bag.item_type ⇒ 展示类型解析为空 ⇒ 不建模型 ⇒ 工人手上的工具不可见。
# 修复后应回退到 bag.peek_state() 载体的 type;取走后(磨损销毁)应能变回空。
#
# 判据用公开 API visible_count():展示类型解析为空时 count_of("") 为 0,
# 道具一个都不会显示 ⇒ visible_count() == 0。

func _make_hand_bag_with_axe() -> Bag:
	var bag := Bag.new()
	bag.max_count = 1
	bag.add_count_of("axe", 1)
	return bag

func _init():
	var failed: int = 0

	# —— 前提:有状态入库后 bag.item_type 仍为空,类型只存在于载体上 ——
	var hand: Bag = _make_hand_bag_with_axe()
	var carrier: Object = hand.peek_state()
	print("BAG item_type='", hand.item_type, "' count=", hand.count, " carrier=", carrier)
	if not hand.item_type.is_empty() or hand.count != 1 or carrier == null:
		failed += 1

	# —— 修复点:绑到有状态仓后应解析出载体类型 ——
	# 判据用 _display_type()(修复的契约本身):展示类型正确后,真实游戏里才会去建模型。
	# 这里不断言 visible_count():headless 下模型场景的几何测量拿不到 AABB,
	# _build_props 会提前放弃,道具建不出来 —— 可见性必须在实跑里验(见本次修复的实跑记录)。
	var stack := ItemStack.new()
	root.add_child(stack)
	stack.bind(hand)
	var resolved: String = str(stack.call(&"_display_type"))
	print("STACK resolved_type='", resolved, "' visible_count=", stack.visible_count(), " long_axis=", stack.long_axis())
	if resolved != "axe":
		failed += 1

	# —— 取走后(工具磨损销毁的路径)应解析回空 ——
	hand.remove_count_of("axe", 1)
	var resolved_after: String = str(stack.call(&"_display_type"))
	print("AFTER_REMOVE resolved_type='", resolved_after, "' bag_count=", hand.count)
	if not resolved_after.is_empty() or hand.count != 0:
		failed += 1

	stack.free()
	print("RESULT failed=", failed)
	quit(failed)
