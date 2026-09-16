class_name ProvideWorkloadTask
extends BTAction

# 供能叶子:工人已就位(任务树先完成移动)后,每 tick 为黑板指向的建筑注入
# in_delta * efficiency * 手持工具倍率 的 workload(building.work()),直到 building.is_work_done()
# 判定"一次生产完成"后返回 SUCCESS——工人离岗,由机器侧决定是否再次请求。
# 驱动期间把实体置为 "work" 状态(前端据此播劳作动画);任务结束由 IdleTask 归 "idle"。
# 建筑无效时 FAILURE,由外层 JobRunnerTask 统一处理归还。
#
# 手持工具(可选):工人随身仓里那件**匹配当前配方 required_tool** 的工具,按
# Tool.work_efficiency_for 放大注入量,并按注入量磨损它;工具因此报废则摘格丢弃并
# FAILURE —— 本次顶岗中止,工人下一轮重新去领工具(见 ManBuildingTask._write_tool_plan)。
# 配方需要工具而工人空手时,注入量降到 Tool.EMPTY_HANDED_EFFICIENCY(0.1 倍):空手仍能
# 干活,只是极慢;配方本就不需要工具时不受影响(恒 1.0)。

const BB_BUILDING: StringName = &"work_building"

@export var efficiency: float = 1

func _enter():
	var entity := get_agent() as Entity
	if entity:
		entity.state = "work"

func _tick(in_delta: float) -> int:
	var entity := get_agent() as Entity
	if not entity:
		return BT.Status.FAILURE
	var raw_building: Variant = get_blackboard().get_var(BB_BUILDING, null, false)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_building) or not (raw_building is Workshop):
		return BT.Status.FAILURE
	var building: Workshop = raw_building
	if entity.state != "work":
		entity.state = "work"
	var labor := entity as Labor
	var tool := _held_tool(labor, building)
	var injected: float = in_delta * efficiency * _tool_factor(tool, building)
	building.work(injected)
	if tool and tool.wear_for_workload(injected):
		# 工具报废:从随身仓摘格丢弃(remove_count 对状态格是丢弃语义)
		labor.carried_bag.remove_count_of(tool.type, 1)
		return BT.Status.FAILURE
	if building.is_work_done():
		return BT.Status.SUCCESS
	return BT.Status.RUNNING

# 随身仓里那件**匹配本配方 required_tool** 的工具;无 / 已 freed / 非 Tool 时返回 null。
func _held_tool(in_labor: Labor, in_building: Workshop) -> Tool:
	if in_labor == null or not is_instance_valid(in_labor.carried_bag):
		return null
	var recipe: RecipeData = in_building.active_recipe
	var wanted: String = recipe.required_tool if recipe else ""
	if wanted.is_empty():
		return null
	var carrier: Object = in_labor.carried_bag.peek_state(wanted)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool

# 手持工具对本配方的效率倍率:配方本就不需要工具 = 1.0(空手即正常,无惩罚);
# 配方需要工具而工人空手 = Tool.EMPTY_HANDED_EFFICIENCY(0.1);持工具则取工具自身倍率。
func _tool_factor(in_tool: Tool, in_building: Workshop) -> float:
	var recipe: RecipeData = in_building.active_recipe
	if recipe == null or recipe.required_tool.is_empty():
		return 1.0
	if in_tool == null:
		return Tool.EMPTY_HANDED_EFFICIENCY
	return in_tool.work_efficiency_for(recipe)
