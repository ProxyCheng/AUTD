extends SceneTree

# AI 行为树测试:结构 + 行为 + 装饰器守卫。改完任何 .tres / 叶子任务后跑一次。
#
#   <godot.exe> --path <项目根> --headless --script res://test/ai_behavior_tree_test.gd
#
# 退出码 = 失败项数(0 = 全过),故可直接被 CI / 脚本判断。
# 说明见 runtime/backend/entities/ai/README.md §6。
#
# A) 卸货步骤 = BTAlwaysSucceed 装饰的共享子树,且 BTSubtree 引用解析成功、真能卸货
# B) 空闲树 = BTRepeat(forever) 循环,且确实永不结束(靠循环重判,不再靠树死掉重建)
# C) 顶岗取工具 = BTAlwaysSucceed 装饰的 Sequence[move,take],且 TakeFromBagTask 已无 optional
# D) Bag / Logistics 核心语义回归
# E) 装饰器守卫:必须有子节点的装饰器不许被当裸叶子挂在组合节点下

const SHED := "res://runtime/backend/entities/ai/shed_load.tres"
const IDLE := "res://runtime/backend/entities/ai/idle.tres"
const HAUL := "res://runtime/backend/entities/ai/transport_haul.tres"
const MAN := "res://runtime/backend/entities/ai/man_building.tres"
const ENEMY := "res://runtime/backend/entities/ai/enemy_siege.tres"

# 这些 BT* 类都是装饰器,语义是"改变其唯一子节点的结果",因此必须有子节点。
# 天生不带子节点、当"调用/占位"用的 BTSubtree 与 BTComment 不在名单内。
const CHILD_REQUIRED_DECORATORS: Array[String] = [
	"BTAlwaysSucceed", "BTAlwaysFail", "BTInvert", "BTRepeat",
	"BTRepeatUntilSuccess", "BTRepeatUntilFailure", "BTTimeLimit", "BTRunLimit",
	"BTDelay", "BTForEach", "BTCooldown", "BTProbability", "BTNewScope",
]

func _load_tree(in_path: String) -> BehaviorTree:
	return ResourceLoader.load(in_path, "", ResourceLoader.CACHE_MODE_IGNORE) as BehaviorTree

# 用 get_class() 比字符串而不是 is,这样插件缺类时脚本仍能编译。
func _scan_bare_decorators(in_task: BTTask, in_tree_name: String, in_out: Array[String]):
	if in_task == null:
		return
	if in_task.get_class() in CHILD_REQUIRED_DECORATORS and in_task.get_child_count() == 0:
		in_out.append("%s:%s" % [in_tree_name, in_task.get_class()])
	for i: int in in_task.get_child_count():
		_scan_bare_decorators(in_task.get_child(i), in_tree_name, in_out)

func _init():
	var failed: int = 0

	# —— A1. 子节点数(man_building 取工具两叶已折叠成 1 个装饰器:8 -> 7) ——
	var expected: Dictionary = {IDLE: 1, HAUL: 5, MAN: 7, SHED: 1}
	for path: String in expected.keys():
		var tree: BehaviorTree = _load_tree(path)
		if tree == null:
			print("FAIL load ", path)
			failed += 1
			continue
		var n: int = tree.root_task.get_child_count()
		var ok: bool = n == int(expected[path])
		print("TREE ", path.get_file(), " root=", tree.root_task.get_class(), " children=", n, " expect=", expected[path], " ok=", ok)
		if not ok:
			failed += 1

	# —— A2. 卸货子树:三棵消费树首个孩子是 BTSubtree 且解析成功 ——
	for path: String in [IDLE, HAUL, MAN]:
		var tree: BehaviorTree = _load_tree(path)
		var host: BTTask = tree.root_task
		if host is BTRepeat:
			host = host.get_child(0)          # 空闲树的 shed 在循环里的序列下
		var first: BTTask = host.get_child(0)
		var sub: BehaviorTree = first.get("subtree") as BehaviorTree
		print("SUBTREE ", path.get_file(), " first_is_subtree=", first is BTSubtree, " resolved=", sub != null)
		if not (first is BTSubtree) or sub == null:
			failed += 1

	# —— A3. 子树自身结构:根是 BTAlwaysSucceed 装饰器,直接装饰那段 BTSequence(不是裸叶子) ——
	var shed: BehaviorTree = _load_tree(SHED)
	var deco: BTTask = shed.root_task
	var seq: BTTask = deco.get_child(0) if deco else null
	var ok_shed: bool = (deco is BTAlwaysSucceed) and deco.get_child_count() == 1 \
			and (seq is BTSequence) and seq.get_child_count() == 3
	print("SHED structure ok=", ok_shed, " root=", shed.root_task.get_class(), " kids=", shed.root_task.get_child_count())
	if not ok_shed:
		failed += 1

	# —— B. 空闲树:根是 BTRepeat(forever),且真跑 10 秒后仍未结束 ——
	var idle: BehaviorTree = _load_tree(IDLE)
	var rep: BTTask = idle.root_task
	var ok_rep: bool = (rep is BTRepeat) and bool(rep.get("forever")) \
			and rep.get_child_count() == 1 and (rep.get_child(0) is BTSequence) \
			and rep.get_child(0).get_child_count() == 2
	print("IDLE repeat forever=", rep.get("forever"), " child_is_sequence=", rep.get_child(0) is BTSequence, " seq_kids=", rep.get_child(0).get_child_count(), " ok=", ok_rep)
	if not ok_rep:
		failed += 1
	# 真跑:空手工人跑 10 秒(> WanderTask.duration=6),应当仍在 RUNNING —— 循环生效、树不结束
	var idler := Labor.new()
	idler.head_bag = Bag.new()
	idler.hand_bag = Bag.new()
	var idle_inst: BTInstance = idle.instantiate(idler, idler.blackboard, idler, idler)
	var idle_status: int = BT.Status.RUNNING
	var idle_ticks: int = 0
	while idle_ticks < 200 and idle_status == BT.Status.RUNNING:
		idle_status = idle_inst.update(0.05)
		idle_ticks += 1
	print("IDLE loop after ", idle_ticks, " ticks status=", idle_status, " (RUNNING=", BT.Status.RUNNING, ")")
	if idle_status != BT.Status.RUNNING:
		failed += 1
	idler.free()

	# —— C1. 顶岗取工具:BTAlwaysSucceed 装饰器直接装饰 Sequence[move,take] ——
	var man: BehaviorTree = _load_tree(MAN)
	var tool_deco: BTTask = man.root_task.get_child(4)
	var tool_seq: BTTask = tool_deco.get_child(0) if tool_deco else null
	var ok_tool: bool = (tool_deco is BTAlwaysSucceed) and tool_deco.get_child_count() == 1 \
			and (tool_seq is BTSequence) and tool_seq.get_child_count() == 2
	print("MAN take_tool decorator ok=", ok_tool, " root_kids=", man.root_task.get_child_count())
	if not ok_tool:
		failed += 1

	# —— C2. TakeFromBagTask 已无 optional,且取不到就 FAILURE ——
	var take := TakeFromBagTask.new()
	var has_optional: bool = take.get("optional") != null
	var miss_labor := Labor.new()
	miss_labor.head_bag = Bag.new()
	miss_labor.hand_bag = Bag.new()
	take.initialize(miss_labor, miss_labor.blackboard, miss_labor)
	var miss_status: int = take.execute(0.0)
	print("TAKE optional_property_present=", has_optional, " miss_status=", miss_status, " (FAILURE=", BT.Status.FAILURE, ")")
	if has_optional or miss_status != BT.Status.FAILURE:
		failed += 1
	miss_labor.free()

	# —— A4. 卸货子树真跑:3 件原木应落进仓(验 BTSubtree 的 agent/黑板传递) ——
	var lvl := Level.new()
	if lvl.logistics == null:
		lvl.logistics = Logistics.new()
	Level.current = lvl
	var target := Bag.new()
	target.item_type = "log"
	target.max_count = 50
	target.access_position = Vector2(1, 1)
	lvl.logistics.register_bag(target)
	var labor := Labor.new()
	labor.head_bag = Bag.new()
	labor.head_bag.max_count = 5
	labor.hand_bag = Bag.new()
	labor.hand_bag.max_count = 1
	labor.head_bag.add_count_of("log", 3)
	labor.position = Vector2(1, 1)
	var shed_inst: BTInstance = shed.instantiate(labor, labor.blackboard, labor, labor)
	var st: int = BT.Status.RUNNING
	var ticks: int = 0
	while ticks < 900 and st == BT.Status.RUNNING:
		st = shed_inst.update(0.05)
		# 取/放已改成"计时搬运":开趟当帧源仓就扣货、货进托管仓飞着,进度由 Logistics.tick 推进
		# (见 ItemTransfer)。树单独跑不会自己走完,故这里必须连世界一起 tick —— 真实游戏里
		# 这两件事本来就是 LevelActor._process → Level.tick 一起驱动的。
		lvl.tick(0.05)
		ticks += 1
	print("SHED-BEHAVIOR status=", st, " ticks=", ticks, " target.count=", target.count, " labor_head=", labor.head_bag.count)
	if target.count != 3 or labor.head_bag.count != 0:
		failed += 1
	labor.free()
	Level.current = null      # 静态指针不置空会留到退出,报一堆 ObjectDB 泄漏
	lvl.free()

	# —— A5. 搬运整趟真跑(transport_haul):取 → 走 → 放,且"放"必须等搬运飞完才收工 ——
	# 回归背景:PutToBagTask 曾把 await_transfer() 的 RUNNING 当成"非 SUCCESS"直接判 FAILURE,
	# 于是叶子开趟后第一 tick 就失败、工人当场走人,而搬运仍由 Logistics 跑完(货照飞)——
	# 看着就是"货还没卸完工人就开始移动"。本项锁住:在途期间整棵树必须仍是 RUNNING,
	# 收工那一刻目标仓必须已经收满。
	var lvl2 := Level.new()
	if lvl2.logistics == null:
		lvl2.logistics = Logistics.new()
	Level.current = lvl2
	var src := Bag.new()
	src.item_type = "log"
	src.max_count = 50
	src.access_position = Vector2(1, 1)
	src.add_count_of("log", 3)
	var dst := Bag.new()
	dst.item_type = "log"
	dst.max_count = 50
	dst.access_position = Vector2(1, 1)
	lvl2.logistics.register_bag(src)
	lvl2.logistics.register_bag(dst)
	var hauler := Labor.new()
	hauler.head_bag = Bag.new()
	hauler.head_bag.max_count = 5
	hauler.hand_bag = Bag.new()
	hauler.hand_bag.max_count = 1
	hauler.position = Vector2(1, 1)
	hauler.blackboard.set_var(TransportTask.BB_SOURCE_BAG, src)
	hauler.blackboard.set_var(TransportTask.BB_DEST_BAG, dst)
	hauler.blackboard.set_var(TransportTask.BB_CARRY_AMOUNT, 3)
	hauler.blackboard.set_var(TransportTask.BB_ITEM_TYPE, "log")
	hauler.blackboard.set_var(TransportTask.BB_TAKE_ACCESS, Vector2(1, 1))
	hauler.blackboard.set_var(TransportTask.BB_PUT_ACCESS, Vector2(1, 1))
	var haul: BehaviorTree = _load_tree(HAUL)
	var haul_inst: BTInstance = haul.instantiate(hauler, hauler.blackboard, hauler, hauler)
	var hst: int = BT.Status.RUNNING
	var hticks: int = 0
	var early_exit: bool = false
	while hticks < 900 and hst == BT.Status.RUNNING:
		hst = haul_inst.update(0.05)
		lvl2.tick(0.05)
		hticks += 1
		# 树收工时货还没到齐 ⇒ 就是"没等搬运飞完"
		if hst != BT.Status.RUNNING and dst.count < 3:
			early_exit = true
	print("HAUL-BEHAVIOR status=", hst, " ticks=", hticks, " src=", src.count, " dst=", dst.count, " early_exit=", early_exit)
	if hst != BT.Status.SUCCESS or dst.count != 3 or src.count != 0 or early_exit:
		failed += 1
	hauler.free()
	Level.current = null
	lvl2.free()

	# —— D. 回归:Bag / Logistics 核心语义 ——
	var logi := Logistics.new()
	var near := Bag.new()
	near.item_type = "log"
	near.max_count = 50
	near.access_position = Vector2(1, 0)
	near.add_count_of("log", 10)
	var base := Bag.new()
	base.item_type = ""
	base.accepts_any_type = true
	base.max_count = Bag.UNLIMITED
	base.preferred_min_count = 0
	base.preferred_max_count = 0
	base.deposit_priority = Bag.DEPOSIT_LAST
	base.withdraw_priority = Bag.WITHDRAW_FIRST
	base.access_position = Vector2(2, 0)
	logi.register_bag(near)
	logi.register_bag(base)
	var dep: Bag = logi.find_nearest_bag("log", Vector2.ZERO, false)
	var fallback: Bag = logi.find_nearest_bag("axe", Vector2.ZERO, false)
	var wit_empty: Bag = logi.find_nearest_bag("log", Vector2.ZERO, true)
	base.add_count_of("log", 5)
	var wit_stock: Bag = logi.find_nearest_bag("log", Vector2.ZERO, true)
	var unlimited_ok: bool = base.add_count_of("stone", 999) == 999 and not base.is_full()
	print("REGRESS deposit_is_near=", dep == near, " fallback_is_base=", fallback == base, " withdraw_empty_is_near=", wit_empty == near, " withdraw_stock_is_base=", wit_stock == base, " unlimited_ok=", unlimited_ok)
	if dep != near or fallback != base or wit_empty != near or wit_stock != base or not unlimited_ok:
		failed += 1
	logi.free()

	# —— E. 装饰器守卫:必须有子节点的装饰器不许被当裸叶子挂在组合节点下 ——
	var bare: Array[String] = []
	for path: String in [IDLE, HAUL, MAN, SHED, ENEMY]:
		_scan_bare_decorators(_load_tree(path).root_task, path.get_file(), bare)
	print("DECORATOR no_bare_leaf=", bare.is_empty(), " offenders=", bare)
	if not bare.is_empty():
		failed += 1

	print("RESULT failed=", failed)
	quit(failed)
