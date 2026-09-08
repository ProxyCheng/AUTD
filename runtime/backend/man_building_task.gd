class_name ManBuildingTask
extends LaborTask

# 顶岗任务:派一名劳工执行共享任务树 man_building.tres(移动到岗位点 →
# 注入 workload),直到 building.is_work_done() 判定"完成一次生产",工人即离岗归还
# 调度池——机器侧(如 Crossbow)可在下次需要时再次请求。供需要人工供能/驱动的建筑使用。
# 参数经工人黑板传递:&"target_position" = 机器格中心(Vector2(building.axis)),
# 岗位角偏移由 man_building.tres 的 MoveToTargetTask.arrival_center_offset 表达
# (= WORK_ENTRY_OFFSET,radius 0 → 精确站角);ProvideWorkloadTask.BB_BUILDING = 建筑。
# .tres 模板每次由 JobRunnerTask.instantiate 深拷贝,多工人共享安全。

const JOB_TREE: BehaviorTree = preload("res://runtime/backend/entities/ai/man_building.tres")

var building: Workshop = null
var entry_position: Vector2 = Vector2.ZERO

func _init(in_building: Workshop, in_entry_position: Vector2, in_required_count: int = 1, in_priority: int = 0):
	super(in_required_count, in_priority)
	building = in_building
	entry_position = in_entry_position
	# 就近调度锚点取岗位角(先走去站角)
	anchor_position = in_entry_position

func make_tree(in_labor: Labor) -> BehaviorTree:
	in_labor.blackboard.set_var(&"target_position", Vector2(building.axis))
	in_labor.blackboard.set_var(ProvideWorkloadTask.BB_BUILDING, building)
	return JOB_TREE
