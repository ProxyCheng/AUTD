class_name LaborTask
extends Node

# 一次性批次任务:凑齐 required_count 个空闲劳工后一次性派发,
# 每个劳工执行一次 make_tree 产出的动作链行为树,全部归还后任务结束。
# 生命周期由 LaborManager 托管(register_task 时挂到其下,完成/取消时释放),
# 因此运行时可在节点面板直接看到每个任务的挂起/执行状态。
# 子类必须实现 make_tree。调度相关:priority 越大越先被满足,
# cost_for 用于"就近调度"打分(越小越优先被选中)。
#
# 运行数据契约(JobRunnerTask 与 LaborManager 共用):
#   BB_JOB_TREE     = 该工人本次要执行的动作链树(make_tree 返回值)
#   BB_ACTIVE_TASK  = 本 LaborTask,供 JobRunnerTask 每 tick 检查 is_cancelled

const BB_JOB_TREE: StringName = &"job_tree"
const BB_ACTIVE_TASK: StringName = &"active_task"

var priority: int = 0
var required_count: int = 1
var anchor_position: Vector2 = Vector2.ZERO  # 工作锚点,供默认 cost_for 计算距离(就近调度)
var is_cancelled: bool = false

func _init(in_required_count: int = 1, in_priority: int = 0):
	var type_name: StringName = get_script().get_global_name()
	name = type_name if not type_name.is_empty() else "LaborTask"
	required_count = in_required_count
	priority = in_priority

func make_tree(in_labor: Labor) -> BehaviorTree:
	assert(false, "LaborTask.make_tree must be overridden")
	return _idle_tree()

func _idle_tree() -> BehaviorTree:
	var tree := BehaviorTree.new()
	tree.set_root_task(IdleTask.new())
	return tree

func cost_for(in_labor: Labor) -> float:
	return in_labor.position.distance_to(anchor_position)
