class_name JobRunnerTask
extends BTAction

# 单个派发批次里"一个工人一份活"的运行器(对应旧 LaborManager.TaskAction):
# 每 tick 先查工人黑板里的 active_task 是否被取消(任务取消/人员流失置 is_cancelled),
# 取消则整棵树 FAILURE(工人随后经 request_work 归还调度池);
# 否则驱动 job_tree(本工人的动作链行为树)的内层 BTInstance,并透传其最终状态。
# job_tree / active_task 由 LaborManager 派发时写入工人黑板,故克隆/复用安全。

var _inner: BTInstance = null

func _tick(in_delta: float) -> int:
	var bb := get_blackboard()
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	var raw_task: Variant = bb.get_var(LaborTask.BB_ACTIVE_TASK, null, false)
	if not is_instance_valid(raw_task) or not (raw_task is LaborTask):
		_finish(bb)
		return BT.Status.FAILURE
	var task: LaborTask = raw_task
	if task.is_cancelled:
		_finish(bb)
		return BT.Status.FAILURE
	if _inner == null:
		var job_tree: BehaviorTree = bb.get_var(LaborTask.BB_JOB_TREE, null, false)
		if job_tree == null:
			_finish(bb)
			return BT.Status.FAILURE
		_inner = job_tree.instantiate(get_agent(), bb, get_agent(), get_agent())
	if _inner == null:
		return BT.Status.FAILURE
	var status: int = _inner.update(in_delta)
	if status == BT.Status.RUNNING:
		return BT.Status.RUNNING
	_inner = null
	_finish(bb)
	return status

func _finish(in_bb: Blackboard):
	if in_bb:
		in_bb.set_var(LaborTask.BB_ACTIVE_TASK, null)
	# 残留物**刻意留着**,不再就地 clear_fungible:卸货失败已改为任务失败(见 PutToBagTask),
	# 若在这里把头顶仓清空,没卸掉的货就被凭空销毁、直接丢件。留着反而有用 —— 工人的下一次
	# 空闲窗口(idle.tres 的 FindDepositBagTask)或下一份活开工前的 shed 步骤会就近把它们重新入仓。
	# 滞留量有界:head_bag.max_count = Logistics.CARRY_CAPACITY,故最多 CARRY_CAPACITY 件,不会堆积。
	# 手仓那件工具(hand_bag)向来不在这里清,由顶岗的归还步骤/空闲卸货负责送回。
