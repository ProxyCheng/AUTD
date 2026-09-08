class_name ProvideWorkloadTask
extends BTAction

# 供能叶子:工人已就位(任务树先完成移动)后,每 tick 为黑板指向的建筑注入
# in_delta * efficiency 的 workload(building.work()),直到 building.is_work_done()
# 判定"一次生产完成"后返回 SUCCESS——工人离岗,由机器侧决定是否再次请求。
# 建筑无效时 FAILURE,由外层 JobRunnerTask 统一处理归还。

const BB_BUILDING: StringName = &"work_building"

@export var efficiency: float = 1

func _enter():
	var entity := get_agent() as Entity
	if entity:
		entity.state = "idle"

func _tick(in_delta: float) -> int:
	var entity := get_agent() as Entity
	if not entity:
		return BT.Status.FAILURE
	var building: Workshop = get_blackboard().get_var(BB_BUILDING, null, false)
	if not building or not is_instance_valid(building):
		return BT.Status.FAILURE
	building.work(in_delta * efficiency)
	if building.is_work_done():
		return BT.Status.SUCCESS
	return BT.Status.RUNNING
