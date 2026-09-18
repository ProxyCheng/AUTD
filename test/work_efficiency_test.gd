extends SceneTree

# Workshop.work_efficiency 回归测试:工具加成必须由 ProvideWorkloadTask 发布到建筑,
# 并在无人值守时由 Workshop.tick 复位(前端工作量条据此决定闪光强弱,见 WorkProgressBar)。
#
#   <godot.exe> --path <项目根> --headless --script res://test/work_efficiency_test.gd
#
# 退出码 = 失败项数(0 = 全过)。
#
# 回归背景:ProvideWorkloadTask 曾把 _tool_factor() 算出的倍率直接乘进注入量后丢弃,
# 建筑只收到乘完的数字,无法知道工人是否在吃工具加成 —— 前端因此没有任何可读的加成信号。
# 本测试驱动**真实链路**(真实 Labor + 手仓里的真实 Axe + 真实 ProvideWorkloadTask
# 的 initialize/execute),而不是手工给 building.work_efficiency 赋值,否则钉不住"算完就丢"。
# 建筑与工人都不进场景树:Workshop.tick 的补员维护有 is_inside_tree 守卫,不会去碰
# LaborManager,从而免去搭建 Level/地图的整套管线(与 test/ai_behavior_tree_test.gd 同做法)。

const DELTA: float = 0.05
# 单件工作量调得远大于测试注入量,保证测试期间不会真的产出一件
# (否则 _produced_this_shift 会让 is_work_done() 提前为真,干扰后续断言)。
const HUGE_WORKLOAD: float = 999.0

var _signal_count: int = 0

func _on_work_efficiency_changed():
	_signal_count += 1

# 造一台不接场景树的作坊:配方固定输出 "log";tick(0.0) 走公开路径让 active_recipe
# 被 _selected_recipe() 选中(与真实补员流程同源),而不是手工塞 active_recipe。
func _make_workshop(in_tool_bonuses: Dictionary[String, float]) -> Workshop:
	var workshop := Workshop.new()
	var recipe := RecipeData.new()
	recipe.label = "Test"
	recipe.output = "log"
	recipe.workload_per_unit = HUGE_WORKLOAD
	recipe.tool_bonuses = in_tool_bonuses
	workshop.recipes = [recipe]
	workshop.tick(0.0)
	assert(workshop.active_recipe == recipe, "active_recipe 未按配方列表选中")
	return workshop

# 造一名不接场景树的工人:两只随身仓手动建(Labor._ready 不跑,与 ai_behavior_tree_test.gd 同做法)。
func _make_labor() -> Labor:
	var labor := Labor.new()
	labor.head_bag = Bag.new()
	labor.head_bag.max_count = 5
	labor.hand_bag = Bag.new()
	labor.hand_bag.max_count = 1
	labor.add_child(labor.head_bag)
	labor.add_child(labor.hand_bag)
	return labor

# 驱动真实 ProvideWorkloadTask 注入一帧;返回执行状态。
func _run_provide(in_labor: Labor, in_workshop: Workshop) -> int:
	var task := ProvideWorkloadTask.new()
	task.initialize(in_labor, in_labor.blackboard, in_labor)
	in_labor.blackboard.set_var(ProvideWorkloadTask.BB_BUILDING, in_workshop)
	return task.execute(DELTA)

func _init():
	var failed: int = 0

	# —— 1. 持斧:配方 tool_bonuses={"axe":2.0} → 发布 2.0,且经信号广播、真的放大注入量 ——
	var bonuses_axe: Dictionary[String, float] = {"axe": 2.0}
	var workshop_axe: Workshop = _make_workshop(bonuses_axe)
	var labor_axe: Labor = _make_labor()
	labor_axe.hand_bag.add_count_of("axe", 1)
	workshop_axe.work_efficiency_changed.connect(_on_work_efficiency_changed)
	var status_axe: int = _run_provide(labor_axe, workshop_axe)
	print("CASE axe_held status=", status_axe, " work_efficiency=", workshop_axe.work_efficiency,
		" signal_count=", _signal_count, " work_accum=", workshop_axe.work_accum, " expect=2.0")
	if not is_equal_approx(workshop_axe.work_efficiency, 2.0):
		failed += 1
	if _signal_count <= 0:
		failed += 1
	# 注入量必须与发布的倍率同源:0.05 × 1.0(efficiency) × 2.0 = 0.1
	if not is_equal_approx(workshop_axe.work_accum, DELTA * 2.0):
		failed += 1

	# —— 2. 同配方空手:恒基准 1.0(工具是纯增益,不是硬需求,空手不惩罚) ——
	var workshop_empty: Workshop = _make_workshop(bonuses_axe)
	var labor_empty: Labor = _make_labor()
	var status_empty: int = _run_provide(labor_empty, workshop_empty)
	print("CASE empty_handed status=", status_empty, " work_efficiency=", workshop_empty.work_efficiency,
		" work_accum=", workshop_empty.work_accum, " expect=1.0")
	if not is_equal_approx(workshop_empty.work_efficiency, 1.0):
		failed += 1
	if not is_equal_approx(workshop_empty.work_accum, DELTA):
		failed += 1

	# —— 3. 无需工具的配方:恒 1.0(即便工人手上恰好有斧头,配方表为空即不认工具) ——
	var bonuses_none: Dictionary[String, float] = {}
	var workshop_plain: Workshop = _make_workshop(bonuses_none)
	var labor_plain: Labor = _make_labor()
	labor_plain.hand_bag.add_count_of("axe", 1)
	var status_plain: int = _run_provide(labor_plain, workshop_plain)
	print("CASE no_tool_recipe status=", status_plain, " work_efficiency=", workshop_plain.work_efficiency, " expect=1.0")
	if not is_equal_approx(workshop_plain.work_efficiency, 1.0):
		failed += 1

	# —— 4. 无人值守复位:上一帧发布的 2.0 必须在值守窗口过期后归 1.0 ——
	# _manned_timer 由 work() 置为 MANNED_TIMEOUT(0.2),tick(0.3) 一次性耗尽它。
	workshop_axe.tick(0.3)
	print("CASE manned_timeout work_efficiency=", workshop_axe.work_efficiency, " expect=1.0")
	if not is_equal_approx(workshop_axe.work_efficiency, 1.0):
		failed += 1

	# 清理:对象都未进树,显式释放避免退出时报 ObjectDB 泄漏。
	labor_axe.free()
	labor_empty.free()
	labor_plain.free()
	workshop_axe.free()
	workshop_empty.free()
	workshop_plain.free()

	print("RESULT failed=", failed)
	quit(failed)
