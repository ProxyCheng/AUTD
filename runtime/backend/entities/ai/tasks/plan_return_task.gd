class_name PlanReturnTask
extends BTAction

# 顶岗归还·规划叶子:任务开头(取工具、干活之前)先决定"手上这件工具还回容器,还是继续留在手上"。
#
# 为什么必须在开工之前定:工人可能带着上一个岗位的工具过来 —— 伐木场握着的斧头被派到石矿,
# 而本机配方要的是镐子。那件工具对本机毫无用处:举着它干活既白占一格,看着也不对(前端按随身仓里
# 第一件工具显示,于是会出现"工人举着斧头采石")。所以先把它放下,再走下一步去取本机要用的工具。
# 反过来,手上正是本机要用的那件就留着 —— 本工程一次顶岗只产一件(Workshop._produced_this_shift),
# 若每件都"还了再领",工人得往返容器数格,工具省下的时间还不够走路。
#
# 放在这里而不是"产出之后"的代价只有一个:最后一件可能正好填满输出仓,机器随即无可行配方
# (active_recipe == null)—— 那种情况下本机不会再派工,工人转入空闲树,由 FindDepositBagTask
# 按同一判定把不再需要的工具就近卸进仓里,故不会留在手上。
#
# 判定:
#   手上无工具 / 工人或随身仓失效 → "留着"计划(无物可还);
#   机器仍是 Workshop 且 active_recipe != null 且 required_tool == 工具类型 → "留着":
#     工人留岗继续干活,还回去就得每件都往返容器数格,斧头省下的时间还不够走路;
#   否则找一只最近的、收得下这件工具的已注册仓(Logistics.find_nearest_bag):
#     有 → 写归还计划;没有(全图无处可收)→ "留着",工人拿着总比丢了好。
#
# 恒 SUCCESS:本叶只改写计划,不移动、不搬运、不失败。
#
# 黑板契约(沿用 ManBuildingTask 派活时写入的同名键,见 man_building.tres):
#   &return_bag    : Bag     归还目标仓;null = 自己留着(ReturnToolTask 见此即空跑)
#   &return_access : Vector2 归还点;"留着"时写工人自身位置 —— MoveToTargetTask 每 tick
#                             从黑板读目标,自身位置距离为零,移动步骤原地即刻达成。

func _tick(_in_delta: float) -> int:
	var agent := get_agent() as Entity
	var labor := agent as Labor
	# 无类型临时变量先判定有效再赋 typed,避免赋值瞬间遇已 freed 的 bag 即崩。
	var raw_carried: Variant = labor.carried_bag if labor else null
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_carried) or not (raw_carried is Bag):
		_plan_keep(agent)
		return BT.Status.SUCCESS
	var carried: Bag = raw_carried
	var tool := _held_tool(carried)
	# 无工具可还,或机器仍要这件工具:留在手上(见文件头)。
	if tool == null or _still_needed(tool.type):
		_plan_keep(agent)
		return BT.Status.SUCCESS
	var target: Bag = _find_return_bag(tool.type, agent.position)
	if target == null:
		# 全图没有收得下这件工具的仓:留着(占一格),等有仓收得下时再还。
		_plan_keep(agent)
		return BT.Status.SUCCESS
	_plan(agent, target)
	return BT.Status.SUCCESS

# 随身仓里那件工具;无 / 已 freed / 非 Tool 时返回 null。
func _held_tool(in_carried: Bag) -> Tool:
	var carrier: Object = in_carried.peek_state()
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool

# 机器是否仍需要该类型工具:黑板 &work_building 仍有效、是 Workshop,且其当前配方
# 还要这件工具(active_recipe != null 且 required_tool == 工具类型)才为真。
# active_recipe == null(如输出仓刚被本件填满)即视为不再需要。
func _still_needed(in_tool_type: String) -> bool:
	var raw_building: Variant = get_blackboard().get_var(ProvideWorkloadTask.BB_BUILDING, null, false)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_building) or not (raw_building is Workshop):
		return false
	var building: Workshop = raw_building
	var recipe: RecipeData = building.active_recipe
	if recipe == null:
		return false
	return recipe.required_tool == in_tool_type

# 最近的"同类型且收得下"的已注册仓(只读查询,见 Logistics.find_nearest_bag);
# 以工人当前位置为距离原点,故挑的是最近的一只。
func _find_return_bag(in_tool_type: String, in_from: Vector2) -> Bag:
	if not Level.current or not Level.current.logistics:
		return null
	return Level.current.logistics.find_nearest_bag(in_tool_type, in_from, false)

# 写"留着"计划:归还仓 null,行走点落回工人自身位置(移动步骤原地即刻达成)。
func _plan_keep(in_agent: Entity):
	_plan(in_agent, null)

# 写归还计划:归还仓为最近可收仓,行走点取该仓装卸点(工人先走到那里再交回)。
func _plan(in_agent: Entity, in_bag: Bag):
	var access: Vector2 = in_agent.position if in_agent else Vector2.ZERO
	if in_bag:
		access = in_bag.access_position
	var bb := get_blackboard()
	bb.set_var(ReturnToolTask.BB_RETURN_BAG, in_bag)
	bb.set_var(ManBuildingTask.BB_RETURN_ACCESS, access)
