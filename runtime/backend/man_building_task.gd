class_name ManBuildingTask
extends LaborTask

# 顶岗任务:派一名劳工执行共享任务树 man_building.tres(需要的话先去容器取工具 →
# 移动到岗位点 → 注入 workload → 干完把工具还回 Stockpile),直到 building.is_work_done()
# 判定"完成一次生产",工人即离岗归还调度池——机器侧(如 Crossbow)可在下次需要时再次请求。
# 供需要人工供能/驱动的建筑使用。
#
# 工具取用按当前配方的 tool_bonuses(接受类型 → 注入倍率):工人已持有其中任意一件即视为满足;
# 否则去最近的有货容器取"接受类型里倍率最高"的一种(见 _find_tool_bag)。
#
# 派发时把运行数据写进工人黑板:
#   &target_position = 机器格中心(Vector2(building.axis)),岗位角偏移由 man_building.tres
#     的 MoveToTargetTask.arrival_center_offset 表达(= WORK_ENTRY_OFFSET,radius 0 → 精确站角);
#   &work_building   = 建筑(ProvideWorkloadTask.BB_BUILDING);
#   &tool_access     = 去哪取工具(有容器=容器装卸点;否则=岗位点,即直接空手开工);
#   &source_bag / &carry_amount / &item_type = 取哪只仓、取几件、取哪一类(给 TakeFromBagTask);
#   &return_access / &return_bag = 干完把工具还去哪(给 ReturnToolTask;无可还的仓则为岗位点)。
# .tres 模板每次由 JobRunnerTask.instantiate 深拷贝,多工人共享安全。

const JOB_TREE: BehaviorTree = preload("res://runtime/backend/entities/ai/man_building.tres")

# 工具取用/归还相关的黑板键(与 man_building.tres 的导出参数对应)。
const BB_TOOL_ACCESS: StringName = &"tool_access"
const BB_RETURN_ACCESS: StringName = &"return_access"
# 一次只领一件工具。
const TOOL_TAKE_AMOUNT: int = 1
# 调度时"手上已握着本机所需工具"的优先级折扣:远大于地图尺寸,压过任何距离差。
const TOOL_HOLD_PRIORITY: float = 100.0

var building: Workshop = null
var entry_position: Vector2 = Vector2.ZERO
# _find_tool_bag 命中的工具类型(供 _write_tool_plan 写进黑板 &item_type)。
# GDScript 无出参,故由该成员回传;取用与写黑板在同一函数内同步完成,不会跨工人串味。
var _matched_tool_type: String = ""

func _init(in_building: Workshop, in_entry_position: Vector2, in_required_count: int = 1, in_priority: int = 10):
	super(in_required_count, in_priority)
	building = in_building
	entry_position = in_entry_position
	# 就近调度锚点取岗位角(先走去站角)
	anchor_position = in_entry_position

func make_tree(in_labor: Labor) -> BehaviorTree:
	in_labor.blackboard.set_var(&"target_position", Vector2(building.axis))
	in_labor.blackboard.set_var(ProvideWorkloadTask.BB_BUILDING, building)
	_write_tool_plan(in_labor)
	_write_return_plan(in_labor)
	return JOB_TREE

# 就近调度 + 工具优先:已经握着本机所需工具的工人优先被派到本机。
# 工具是"按件"的、全图往往只有一两把,而默认 cost_for(LaborTask)只看距离 —— 于是会派一个
# 空手工人过来,把工具留在另一个闲置工人手上(空闲树见 &work_building 仍要这件工具就不卸,见
# FindDepositBagTask),本机只能空手开工(效率差 20 倍,见 Tool.EMPTY_HANDED_EFFICIENCY)。
# 扣一个远大于地图尺寸的常量,确保"手上有工具"压过任何距离差;配方不接受工具(表为空)时
# _holds_accepted_tool 恒 false,行为与默认一致。
func cost_for(in_labor: Labor) -> float:
	var cost: float = super.cost_for(in_labor)
	if _holds_accepted_tool(in_labor):
		cost -= TOOL_HOLD_PRIORITY
	return cost

# 备好"要不要取工具、去哪取":工人已持有配方接受的工具 / 配方不接受工具 / 全图没有该工具的
# 容器 → 源仓置 null 且行走目标落到岗位点,等价直接空手开工(TakeFromBagTask.optional = true)。
func _write_tool_plan(in_labor: Labor):
	var source := _find_tool_bag(in_labor)
	in_labor.blackboard.set_var(TransportTask.BB_SOURCE_BAG, source)
	in_labor.blackboard.set_var(TransportTask.BB_CARRY_AMOUNT, TOOL_TAKE_AMOUNT)
	# 显式写命中的工具类型:通配仓(accepts_any_type)的 item_type 为空,只按仓的 item_type 取
	# 会一件都取不到(move_to 拒绝空类型)。无仓可去时写空串,TakeFromBagTask 随即回退仓的 item_type。
	in_labor.blackboard.set_var(TransportTask.BB_ITEM_TYPE, _matched_tool_type)
	in_labor.blackboard.set_var(BB_TOOL_ACCESS,
			source.access_position if source else building.work_entry_position())

# 备好"开工前把工具还去哪":只还"本单用不上的工具"。
# 手上没有工具 → 无物可还,归还点落到岗位点,ReturnToolTask 空跑跳过(否则每件白跑一趟容器);
# 手上正是本单接受的工具 → 留着接着用 —— 每件一单(见 Workshop.is_work_done),若每单都
# "还了再领",工人就得往返容器数格,工具省下的时间还不够走路。故工具一直握到本机不再需要它
# (配方换掉)或它报废为止。
# 这里写的只是初稿:去留由 PlanReturnTask 在任务开头(取工具、干活之前)重判并覆盖 —— 工人可能
# 带着上一岗的工具过来(伐木场的斧头到了石矿),那件对本机毫无用处,必须开工前放下。
func _write_return_plan(in_labor: Labor):
	var held: Tool = _held_tool(in_labor)
	var target: Bag = null
	if held != null and not _is_accepted(held.type):
		target = _find_return_bag(held.type)
	in_labor.blackboard.set_var(ReturnToolTask.BB_RETURN_BAG, target)
	in_labor.blackboard.set_var(BB_RETURN_ACCESS,
			target.access_position if target else building.work_entry_position())

# 当前配方所需工具的容器:按接受类型从强到弱,取第一类"还有货"且离岗位点最近的仓;
# 已持有接受工具、配方不接受工具(表为空)、或全图无货时返回 null。
# 命中的类型写入 _matched_tool_type —— 通配仓的 item_type 为空,取货叶子必须拿到显式类型,
# 故不能只回传 Bag(见 _write_tool_plan)。
# 注:不实现"手上已有较弱工具时再去换更强的一把" —— 持有任意接受工具即视为满足(已知后续项)。
func _find_tool_bag(in_labor: Labor) -> Bag:
	_matched_tool_type = ""
	if _holds_accepted_tool(in_labor):
		return null
	for tool_type: String in _accepted_tools():
		var bag: Bag = _nearest_bag(tool_type, true)
		if bag:
			_matched_tool_type = tool_type
			return bag
	return null

# 归还目标:同类型、且收得下(未满)的仓,离岗位点最近的一只。
func _find_return_bag(in_tool_type: String) -> Bag:
	return _nearest_bag(in_tool_type, false)

# 在 Logistics 已注册的仓里挑最近的一只(只读查询,唯一实现在 Logistics.find_nearest_bag):
# 类型匹配,且按 in_want_supply 取角色 —— 取工具要"有货"(count > 0),还工具要"收得下"(未满)。
# 距离原点取岗位点:工人从岗位出发去取/还。
func _nearest_bag(in_item_type: String, in_want_supply: bool) -> Bag:
	if not Level.current or not Level.current.logistics:
		return null
	return Level.current.logistics.find_nearest_bag(
			in_item_type, building.work_entry_position(), in_want_supply)

# 当前配方接受的工具类型,按注入倍率降序(倍率高的优先考虑);无配方 / 表为空时返回空数组。
func _accepted_tools() -> Array[String]:
	var recipe: RecipeData = building.active_recipe
	if recipe == null:
		return []
	var bonuses := recipe.tool_bonuses
	var types: Array[String] = []
	for tool_type: String in bonuses:
		types.append(tool_type)
	types.sort_custom(func(in_a: String, in_b: String) -> bool:
		return bonuses[in_a] > bonuses[in_b])
	return types

# 工人手仓(hand_bag)里是否已持有**本配方接受的任意一种**工具(工具是"按件"的,取件前先看手上有没有)。
# 直接遍历配方表,不走 _accepted_tools():本判定只要"有没有",不需要按倍率排序,而它被
# cost_for 调用、cost_for 又被调度比较器反复调用。
func _holds_accepted_tool(in_labor: Labor) -> bool:
	var recipe: RecipeData = building.active_recipe
	if recipe == null:
		return false
	for tool_type: String in recipe.tool_bonuses:
		if _already_holds(in_labor, tool_type):
			return true
	return false

# 该类型是否被当前配方接受(tool_bonuses 表里是否登记);无配方 / 表为空 = 什么都不接受。
func _is_accepted(in_tool_type: String) -> bool:
	var recipe: RecipeData = building.active_recipe
	return recipe != null and recipe.tool_bonuses.has(in_tool_type)

# 工人手仓里是否已有该类型的工具(工具是"按件"的,取件前先看手上有没有)。
func _already_holds(in_labor: Labor, in_tool_type: String) -> bool:
	if not is_instance_valid(in_labor.hand_bag):
		return false
	var carrier: Object = in_labor.hand_bag.peek_state(in_tool_type)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return false
	var tool: Tool = carrier
	return tool.type == in_tool_type

# 工人手仓里那件工具(任意类型);无 / 已 freed / 非 Tool 时返回 null。
func _held_tool(in_labor: Labor) -> Tool:
	if not is_instance_valid(in_labor.hand_bag):
		return null
	var carrier: Object = in_labor.hand_bag.peek_state()
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool
