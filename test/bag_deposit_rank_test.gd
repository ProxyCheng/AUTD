extends SceneTree

# Logistics.find_nearest_bag 的落库分层回归测试。
#
# 规则(见 Bag.deposit_rank —— 原 Logistics._deposit_rank,已迁到仓上作为唯一实现):
#   2 = 同类型仓,且 count_of < preferred_max_count(该仓自己声明"还想装到这么多")
#   1 = 同类型仓,且未满
#   0 = 通配仓(如 MainBaseBag)—— 只作最后兜底
# 分层是落库排序的首要键,deposit_priority 只在同层内比较;取货方向不受影响(仍比 withdraw_priority)。
#
# 回归背景:落库原先只比 deposit_priority,而 MainBaseBag 声明 DEPOSIT_FIRST = 1、其余仓默认 0,
# 于是主基地无条件胜出 —— 哪怕同类型的作坊产出仓就在旁边、哪怕主基地在 140 格外,工人也总是把
# 用不上的工具送回主基地(实测)。
#
#   <godot.exe> --path <项目根> --headless --script res://test/bag_deposit_rank_test.gd
#
# 退出码 = 失败项数(0 = 全过)。

func _bag(in_item_type: String, in_max: int, in_pref_min: int, in_pref_max: int, in_at: Vector2) -> Bag:
	var bag := Bag.new()
	bag.item_type = in_item_type
	bag.max_count = in_max
	bag.preferred_min_count = in_pref_min
	bag.preferred_max_count = in_pref_max
	bag.access_position = in_at
	return bag

func _init():
	var failed: int = 0
	var logi := Logistics.new()

	var base := MainBaseBag.new()
	base.access_position = Vector2.ZERO
	logi.register_bag(base)

	# 工具坊的产出仓:同类型、preferred_max = 0 → 落库分层第 1 层
	var axe_out: Bag = _bag("axe", 30, 0, 0, Vector2(1, 0))
	logi.register_bag(axe_out)

	# —— 1. 有同类型未满仓 → 落它,而不是主基地(主基地更近也没用) ——
	var got: Bag = logi.find_nearest_bag("axe", Vector2.ZERO, false)
	print("CASE prefer_type_bag got_axe_out=", got == axe_out, " got_main_base=", got == base, " expect=axe_out")
	if got != axe_out:
		failed += 1

	# —— 2. 同类型仓满 → 落主基地兜底 ——
	axe_out.add_count(30)
	got = logi.find_nearest_bag("axe", Vector2(1, 0), false)
	print("CASE fallback_to_base got_main_base=", got == base, " expect=MainBase")
	if got != base:
		failed += 1
	axe_out.remove_count(30)

	# —— 3. preferred_max 未到的同类型仓 > 仅"未满"的同类型仓(后者近 49 格也没用) ——
	var log_in: Bag = _bag("log", 30, 30, 30, Vector2(50, 50))
	logi.register_bag(log_in)
	var log_out: Bag = _bag("log", 30, 0, 0, Vector2(1, 0))
	logi.register_bag(log_out)
	got = logi.find_nearest_bag("log", Vector2(1, 0), false)
	print("CASE rank2_beats_rank1 got_log_in=", got == log_in, " got_log_out=", got == log_out, " expect=log_in")
	if got != log_in:
		failed += 1

	# —— 4. 取货方向不变:主基地 withdraw_priority = WITHDRAW_FIRST,有货时仍优先 ——
	base.add_count_of("axe", 2)
	got = logi.find_nearest_bag("axe", Vector2(1, 0), true)
	print("CASE withdraw_unchanged got_main_base=", got == base, " expect=MainBase")
	if got != base:
		failed += 1

	# —— 5. 主基地空 → 才落到有货的专仓(取货兜底:主基地有货就取它,否则才走调度) ——
	axe_out.add_count(3)
	base.remove_count_of("axe", 2)
	got = logi.find_nearest_bag("axe", Vector2.ZERO, true)
	print("CASE withdraw_fallback got_axe_out=", got == axe_out, " expect=axe_out")
	if got != axe_out:
		failed += 1

	# —— 6. 全图无货 → null(交给调度侧继续等/补,本查询不编造目标) ——
	axe_out.remove_count(3)
	got = logi.find_nearest_bag("axe", Vector2.ZERO, true)
	print("CASE withdraw_nothing got_null=", got == null, " expect=<null>")
	if got != null:
		failed += 1

	# —— 7. 搬运能力角色(仓储型 / 纯需求方) ——
	# 判据搬到 Bag 上后(见 Bag.is_pure_demand / available_to_provide),这两个角色必须
	# 仍然成立:仓储型可存可取(可给量 = 全部存量),纯需求方只进不出(绝不被抽走)。
	var storage: Bag = _bag("stone", 30, 0, 30, Vector2(2, 0))
	storage.add_count_of("stone", 5)
	print("CASE storage_role can_provide=", storage.can_provide("stone"),
			" available=", storage.available_to_provide("stone"),
			" rank=", storage.deposit_rank("stone"), " expect=true/5/2")
	if not storage.can_provide("stone") or storage.available_to_provide("stone") != 5 \
			or storage.deposit_rank("stone") != 2:
		failed += 1

	var demand: Bag = _bag("stone", 30, 30, 30, Vector2(3, 0))
	demand.add_count_of("stone", 5)
	print("CASE demand_role can_provide=", demand.can_provide("stone"),
			" can_accept=", demand.can_accept("stone"),
			" rank=", demand.deposit_rank("stone"), " expect=false/true/2")
	if demand.can_provide("stone") or not demand.can_accept("stone") \
			or demand.deposit_rank("stone") != 2:
		failed += 1
	storage.free()
	demand.free()

	base.free()
	axe_out.free()
	log_in.free()
	log_out.free()
	logi.free()

	print("RESULT failed=", failed)
	quit(failed)
