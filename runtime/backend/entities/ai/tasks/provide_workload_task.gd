class_name ProvideWorkloadTask
extends BTAction

# 供能叶子:工人已就位(任务树先完成移动)后,每 tick 为黑板指向的建筑注入
# in_delta * efficiency * 手持工具倍率 的 workload(building.work()),直到 building.is_work_done()
# 判定"一次生产完成"后返回 SUCCESS——工人离岗,由机器侧决定是否再次请求。
# 驱动期间把实体置为 "work" 状态(前端据此播劳作动画);任务结束由 IdleTask 归 "idle"。
# 建筑无效时 FAILURE,由外层 JobRunnerTask 统一处理归还。
#
# 手持工具(纯增益,可选):配方经 tool_bonuses 声明接受的工具类型 → 注入倍率;工人手仓(hand_bag)里
# 持有其中任意一件时,取**表内倍率最高**的那件放大注入量,并按注入量磨损它;工具因此报废则摘格
# 丢弃并 FAILURE —— 本次顶岗中止,工人下一轮重新去领工具(见 ManBuildingTask._write_tool_plan)。
# 空手 = 基准 1.0:工具是纯增益而非硬需求,没拿到工具不会拖慢生产,只是少了那份额外加成。

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
	# 倍率只算一次:先发布给建筑(前端据此把加成强弱表现成工作量条闪光),
	# 再用同一值放大本帧注入量 —— 两处必须同源,否则表现与实际效率会漂移。
	var factor: float = _tool_factor(tool, building)
	building.work_efficiency = factor
	var injected: float = in_delta * efficiency * factor
	building.work(injected)
	if tool:
		# 这件工具真的派上用场了:清零"未使用计时"(见 Tool.unused_time)。
		tool.mark_used()
		if tool.wear_for_workload(injected):
			# 工具报废:从手仓摘格丢弃(remove_count 对状态格是丢弃语义)
			labor.hand_bag.remove_count_of(tool.type, 1)
			return BT.Status.FAILURE
	if building.is_work_done():
		return BT.Status.SUCCESS
	return BT.Status.RUNNING

# 手仓(hand_bag)里持有的**本配方接受的工具**中加成最高的一件;无 / 已 freed / 非 Tool 时返回 null。
# 配方表为空(无需工具)时恒 null —— 空手即正常,不必找工具。
func _held_tool(in_labor: Labor, in_building: Workshop) -> Tool:
	if in_labor == null or not is_instance_valid(in_labor.hand_bag):
		return null
	var recipe: RecipeData = in_building.active_recipe
	if recipe == null or recipe.tool_bonuses.is_empty():
		return null
	var best: Tool = null
	var best_bonus: float = 0.0
	for tool_type: String in recipe.tool_bonuses:
		var carrier: Object = in_labor.hand_bag.peek_state(tool_type)
		# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
		if not is_instance_valid(carrier) or not (carrier is Tool):
			continue
		var tool: Tool = carrier
		var bonus: float = recipe.tool_bonuses[tool_type]
		if best == null or bonus > best_bonus:
			best = tool
			best_bonus = bonus
	return best

# 手持工具对本配方的效率倍率:配方不声明工具(表为空)或工人空手 = 基准 1.0(工具是纯增益,
# 不是硬需求);持工具则取配方给该工具类型的倍率(表里查不到该类型这种异常情况兜底 1.0)。
func _tool_factor(in_tool: Tool, in_building: Workshop) -> float:
	var recipe: RecipeData = in_building.active_recipe
	if recipe == null or in_tool == null:
		return 1.0
	return recipe.tool_bonuses.get(in_tool.type, 1.0)
