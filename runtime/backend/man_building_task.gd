class_name ManBuildingTask
extends LaborTask

# 顶岗任务:派一名劳工执行共享任务树 man_building.tres(需要的话先去容器取工具 →
# 移动到岗位点 → 注入 workload → 干完把工具还回 Stockpile),直到 building.is_work_done()
# 判定"完成一次生产",工人即离岗归还调度池——机器侧(如 Crossbow)可在下次需要时再次请求。
# 供需要人工供能/驱动的建筑使用。
#
# 派发时把运行数据写进工人黑板:
#   &target_position = 机器格中心(Vector2(building.axis)),岗位角偏移由 man_building.tres
#     的 MoveToTargetTask.arrival_center_offset 表达(= WORK_ENTRY_OFFSET,radius 0 → 精确站角);
#   &work_building   = 建筑(ProvideWorkloadTask.BB_BUILDING);
#   &tool_access     = 去哪取工具(有容器=容器装卸点;否则=岗位点,即直接空手开工);
#   &source_bag / &carry_amount = 取哪只仓、取几件(给 TakeFromBagTask);
#   &return_access / &return_bag = 干完把工具还去哪(给 ReturnToolTask;无可还的仓则为岗位点)。
# .tres 模板每次由 JobRunnerTask.instantiate 深拷贝,多工人共享安全。

const JOB_TREE: BehaviorTree = preload("res://runtime/backend/entities/ai/man_building.tres")

# 工具取用/归还相关的黑板键(与 man_building.tres 的导出参数对应)。
const BB_TOOL_ACCESS: StringName = &"tool_access"
const BB_RETURN_ACCESS: StringName = &"return_access"
# 一次只领一件工具。
const TOOL_TAKE_AMOUNT: int = 1

var building: Workshop = null
var entry_position: Vector2 = Vector2.ZERO

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

# 备好"要不要取工具、去哪取":工人已持有匹配工具 / 配方不需要工具 / 全图没有该工具的容器
# → 源仓置 null 且行走目标落到岗位点,等价直接空手开工(TakeFromBagTask.optional = true)。
func _write_tool_plan(in_labor: Labor):
	var source := _find_tool_bag(in_labor)
	in_labor.blackboard.set_var(TransportTask.BB_SOURCE_BAG, source)
	in_labor.blackboard.set_var(TransportTask.BB_CARRY_AMOUNT, TOOL_TAKE_AMOUNT)
	in_labor.blackboard.set_var(BB_TOOL_ACCESS,
			source.access_position if source else building.work_entry_position())

# 备好"开工前把工具还去哪":只还"本单用不上的工具"。
# 手上没有工具 → 无物可还,归还点落到岗位点,ReturnToolTask 空跑跳过(否则每件白跑一趟容器);
# 手上正是本单要用的工具 → 留着接着用 —— 每件一单(见 Workshop.is_work_done),若每单都
# "还了再领",工人就得往返容器数格,斧头省下的时间还不够走路。故工具一直握到本机不再需要它
# (配方换掉)或它报废为止。
# 这里写的只是初稿:去留由 PlanReturnTask 在任务开头(取工具、干活之前)重判并覆盖 —— 工人可能
# 带着上一岗的工具过来(伐木场的斧头到了石矿),那件对本机毫无用处,必须开工前放下。
func _write_return_plan(in_labor: Labor):
	var held: Tool = _held_tool(in_labor)
	var target: Bag = null
	if held != null and held.type != _required_tool():
		target = _find_return_bag(held.type)
	in_labor.blackboard.set_var(ReturnToolTask.BB_RETURN_BAG, target)
	in_labor.blackboard.set_var(BB_RETURN_ACCESS,
			target.access_position if target else building.work_entry_position())

# 当前配方所需工具的容器:类型匹配且还有货,取离岗位点最近的一只;
# 已持有匹配工具、配方不需要工具、或全图无此工具时返回 null。
func _find_tool_bag(in_labor: Labor) -> Bag:
	var tool_type: String = _required_tool()
	if tool_type.is_empty() or _already_holds(in_labor, tool_type):
		return null
	return _nearest_bag(tool_type, true)

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

# 当前配方所需的工具类型;无配方 / 配方不需要工具时返回 ""。
func _required_tool() -> String:
	var recipe: RecipeData = building.active_recipe
	if recipe == null:
		return ""
	return recipe.required_tool

# 工人随身仓里是否已有该类型的工具(工具是"按件"的,取件前先看手上有没有)。
func _already_holds(in_labor: Labor, in_tool_type: String) -> bool:
	if not is_instance_valid(in_labor.carried_bag):
		return false
	var carrier: Object = in_labor.carried_bag.peek_state(in_tool_type)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return false
	var tool: Tool = carrier
	return tool.type == in_tool_type

# 工人随身仓里那件工具(任意类型);无 / 已 freed / 非 Tool 时返回 null。
func _held_tool(in_labor: Labor) -> Tool:
	if not is_instance_valid(in_labor.carried_bag):
		return null
	var carrier: Object = in_labor.carried_bag.peek_state()
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool
