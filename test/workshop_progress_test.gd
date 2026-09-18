extends SceneTree

# Workshop.progress 回归测试:无在产件时必须归零,不得留上一件的陈旧值。
#
# 回归背景:progress 只在 Workshop._apply_workload 里、且只在"有锁存在产件(_unit_recipe)"时
# 被写入。一件产出后若当场没有可执行配方(工人刚吃掉最后一份原料 / 输出仓刚满),第 243 行会把
# _unit_recipe 清成 null,而 progress 不再被写 —— 于是停在上一帧的值(≈1.0)。作坊随即变空闲、
# 放走工人;物流补料后重新招工,在**下一名工人走到岗位之前**进度条一直是满格(实测 0.999)。
#
#   <godot.exe> --path <项目根> --headless --script res://test/workshop_progress_test.gd
#
# 退出码 = 失败项数(0 = 全过)。
#
# 作坊与仓都不进场景树:Workshop.tick 的补员维护有 is_inside_tree 守卫,不会去碰 LaborManager,
# 从而免去搭建 Level/地图的整套管线(与 test/work_efficiency_test.gd 同做法)。

const DELTA: float = 0.0333
const WORKLOAD: float = 4.0

# 造一台不接场景树的作坊:配方 = 1 石头 → 1 原木,单件工作量 WORKLOAD。
# 石头仓预置 in_stones 块;原木输出仓容量 in_output_capacity。
# _ready 走不到(未进树、cell 为空),故两只仓手工建并手动登记 —— 等价 _make_bag 的产物。
func _make_workshop(in_stones: int, in_output_capacity: int) -> Workshop:
	var workshop := Workshop.new()
	var recipe := RecipeData.new()
	recipe.label = "Test"
	recipe.output = "log"
	recipe.workload_per_unit = WORKLOAD
	var stone_input := RecipeInputData.new()
	stone_input.item_type = "stone"
	stone_input.count = 1
	recipe.inputs = [stone_input]
	workshop.recipes = [recipe]
	var stone_bag := Bag.new()
	stone_bag.item_type = "stone"
	stone_bag.max_count = 9
	stone_bag.add_count(in_stones)
	workshop.add_child(stone_bag)
	workshop._bags.append(stone_bag)
	var log_bag := Bag.new()
	log_bag.item_type = "log"
	log_bag.max_count = in_output_capacity
	workshop.add_child(log_bag)
	workshop.output_bags["log"] = log_bag
	workshop._bags.append(log_bag)
	return workshop

# 持续注入直到"没有锁存在产件"(即产出后当场无配方可执行),返回注入帧数。
func _work_until_idle(in_workshop: Workshop) -> int:
	var frames: int = 0
	while frames < 1000:
		in_workshop.work(DELTA)
		frames += 1
		if in_workshop._unit_recipe == null:
			break
	return frames

func _init():
	var failed: int = 0

	# —— 1. 产完一件后原料耗尽:进度条必须归零,而不是停在临产前的 ≈1.0 ——
	var workshop: Workshop = _make_workshop(1, 30)
	if not is_equal_approx(workshop.progress, 0.0):
		failed += 1
	var frames: int = _work_until_idle(workshop)
	print("CASE after_unit frames=", frames, " accum=", workshop.work_accum,
		" progress=", workshop.progress, " needs_worker=", workshop._needs_worker(), " expect=0.0")
	if not is_equal_approx(workshop.progress, 0.0):
		failed += 1
	# 产出确实发生了(否则上一条断言等于没测):原木入仓 1 件
	var log_bag: Bag = workshop._bags[1]
	if log_bag.count != 1:
		failed += 1

	# —— 2. 物流补料后重新招工:等工人到位期间进度条仍应是 0 ——
	var stone_bag: Bag = workshop._bags[0]
	stone_bag.add_count(1)
	print("CASE waiting_for_worker progress=", workshop.progress,
		" needs_worker=", workshop._needs_worker(), " expect=0.0/true")
	if not is_equal_approx(workshop.progress, 0.0):
		failed += 1
	if not workshop._needs_worker():
		failed += 1
	workshop.free()

	# —— 3. 一开始就无可行配方:进度条恒 0(不能保留构造期的任何值) ——
	var starved: Workshop = _make_workshop(0, 30)
	starved.work(DELTA)
	print("CASE no_recipe progress=", starved.progress,
		" needs_worker=", starved._needs_worker(), " expect=0.0/false")
	if not is_equal_approx(starved.progress, 0.0):
		failed += 1
	starved.free()

	# —— 4. 输出仓满:与 1 同源的第二条路径(产完一件后无可执行配方) ——
	var full: Workshop = _make_workshop(9, 1)
	var full_frames: int = _work_until_idle(full)
	print("CASE output_full frames=", full_frames, " accum=", full.work_accum,
		" progress=", full.progress, " expect=0.0")
	if not is_equal_approx(full.progress, 0.0):
		failed += 1
	full.free()

	# —— 5. 在产件中途:progress 必须等于 已累计/工作量(归零逻辑不得误伤在产件) ——
	var mid: Workshop = _make_workshop(9, 30)
	mid.work(WORKLOAD * 0.5)
	print("CASE mid_unit progress=", mid.progress, " expect=0.5")
	if not is_equal_approx(mid.progress, 0.5):
		failed += 1
	mid.free()

	print("RESULT failed=", failed)
	quit(failed)
