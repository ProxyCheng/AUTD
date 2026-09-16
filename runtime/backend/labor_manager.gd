class_name LaborManager
extends Node

# 劳工调度中心: Labor 进场/离场时注册/注销自己,
# 其他系统(Workshop / 未来的 LogisticsManager)通过 register_task / cancel_task 提交一次性批次任务。
# 任务节点由管理器托管,运行时挂在 LaborManager 节点下,便于节点面板查看任务清单。
#
# 任务 = 需要的人数 + 每人一棵动作链行为树(LaborTask.make_tree 按工人生成)。
# 调度策略: 按 priority(降序,同优先级先到先得)依次尝试派发;
# 只有当前空闲人数 >= required_count 才整批派发,人选取 cost_for 最优(默认最近)的劳工;
# 派发后把整棵 JobRunnerTask 包装树推给工人替换其当前任务树(替代旧的 TaskAction 链)。
# 每人跑完自己的树即归还调度池,全部归还后任务结束(发 task_completed);
# 中途取消则 JobRunnerTask 在工人下一 tick 检查到取消并以 FAILURE 中止,全部撤出后发 task_cancelled。
# 无活可派的工人拿到空闲树(idle.tres):先卸下随身仓里"现在用不上"的物品,再原地游荡待命。


# 空闲树(§5.3:行为链落 .tres,不代码组装):卸货 → 游荡。模板由 instantiate 深拷贝,多工人共用安全。
const IDLE_TREE: BehaviorTree = preload("res://runtime/backend/entities/ai/idle.tres")


class TaskRecord:
	var task: LaborTask = null
	var sequence: int = 0
	var workers: Array[Labor] = []

	func _init(in_task: LaborTask, in_sequence: int):
		task = in_task
		sequence = in_sequence


signal task_completed(task: LaborTask)
signal task_cancelled(task: LaborTask)

var _idle: Dictionary = {}  # { labor: true } 空闲待命劳工
var _assigned: Dictionary = {}  # { labor: TaskRecord } 正为任务工作的劳工
var _records: Dictionary = {}  # { task: TaskRecord } 注册中(待派发/执行中)的任务
var _pending: Array = []  # 尚未凑齐人手、待派发的任务记录(Array[TaskRecord])
var _next_sequence: int = 0

func register_labor(in_labor: Labor):
	_idle.set(in_labor, true)
	_schedule(null)

func unregister_labor(in_labor: Labor):
	_idle.erase(in_labor)
	var record: TaskRecord = _assigned.get(in_labor)
	if record:
		# 劳工中途离开(死亡/换脑):整批作废,其余工人由 JobRunnerTask 检测到取消后撤出
		record.task.is_cancelled = true
		_release_worker(in_labor, record)
	_schedule(null)

func register_task(in_task: LaborTask) -> LaborTask:
	assert(not _records.has(in_task), "LaborTask already registered")
	var record := TaskRecord.new(in_task, _next_sequence)
	_next_sequence += 1
	in_task.name = "%s_%d" % [in_task.name, record.sequence]
	add_child(in_task)
	in_task.owner = owner
	_records.set(in_task, record)
	_pending.append(record)
	_schedule(null)
	return in_task

func cancel_task(in_task: LaborTask):
	if not in_task or in_task.is_cancelled:
		return
	in_task.is_cancelled = true
	var record: TaskRecord = _records.get(in_task)
	if not record:
		return
	if record.workers.is_empty():
		_pending.erase(record)
		_records.erase(in_task)
		task_cancelled.emit(in_task)
		_release_task(in_task)

# 劳工当前任务树已结束,请求下一棵(由 Labor.create_tree 调用)。
# 返回要执行的行为树;无活可派时返回空闲树(idle.tres:先卸下用不上的随身物品,再原地游荡)。
func request_work(in_labor: Labor) -> BehaviorTree:
	var record: TaskRecord = _assigned.get(in_labor)
	if record:
		_release_worker(in_labor, record)
	_idle.set(in_labor, true)
	var tree: BehaviorTree = _schedule(in_labor)
	if tree:
		return tree
	return _idle_tree(in_labor)

func _schedule(in_requester: Labor) -> BehaviorTree:
	var requester_tree: BehaviorTree = null
	var ordered: Array = _pending.duplicate()
	ordered.sort_custom(_record_comes_first)
	for record: TaskRecord in ordered:
		if not _pending.has(record):
			continue
		if record.task.is_cancelled:
			continue
		if _idle.size() < record.task.required_count:
			continue
		var tree: BehaviorTree = _dispatch(record, in_requester)
		if tree:
			requester_tree = tree
		if _idle.is_empty():
			break
	return requester_tree

func _dispatch(in_record: TaskRecord, in_requester: Labor) -> BehaviorTree:
	var idle_workers: Array = _idle.keys()
	idle_workers.sort_custom(func(in_a: Labor, in_b: Labor) -> bool:
		return in_record.task.cost_for(in_a) < in_record.task.cost_for(in_b))
	var chosen: Array = idle_workers.slice(0, in_record.task.required_count)
	_pending.erase(in_record)
	for worker: Labor in chosen:
		_idle.erase(worker)
		_assigned.set(worker, in_record)
		in_record.workers.append(worker)
	var requester_tree: BehaviorTree = null
	for worker: Labor in chosen:
		var tree := _make_job_wrapper(in_record.task, worker)
		if worker == in_requester:
			# 请求者此刻正处于 create_tree 中,包装树由返回路径直接挂上
			requester_tree = tree
		else:
			_assign_tree(worker, tree)
	return requester_tree

# 每个工人一棵包装树:根为 JobRunnerTask,运行数据(job_tree / active_task)写进该工人黑板。
func _make_job_wrapper(in_task: LaborTask, in_labor: Labor) -> BehaviorTree:
	var job_tree: BehaviorTree = in_task.make_tree(in_labor)
	in_labor.blackboard.set_var(LaborTask.BB_JOB_TREE, job_tree)
	in_labor.blackboard.set_var(LaborTask.BB_ACTIVE_TASK, in_task)
	var wrapper := BehaviorTree.new()
	wrapper.set_root_task(JobRunnerTask.new())
	return wrapper

# 把一棵新任务树推给空闲中的劳工,替换其当前树(等价旧 _give_action 的"立即换活")。
func _assign_tree(in_labor: Labor, in_tree: BehaviorTree):
	in_labor.begin_tree(in_tree)

func _release_worker(in_labor: Labor, in_record: TaskRecord):
	_assigned.erase(in_labor)
	in_record.workers.erase(in_labor)
	if in_record.workers.is_empty():
		_finish_record(in_record)

func _finish_record(in_record: TaskRecord):
	_records.erase(in_record.task)
	if in_record.task.is_cancelled:
		task_cancelled.emit(in_record.task)
	else:
		task_completed.emit(in_record.task)
	_release_task(in_record.task)

func _release_task(in_task: LaborTask):
	if in_task.get_parent() == self:
		remove_child(in_task)
		in_task.queue_free()

# 无活可派的待命树:先卸下随身仓里"现在用不上"的物品(见 idle.tres),再原地游荡;
# 待派活时整棵树被任务树替换。in_labor 预留给按工人差异定制的空闲行为,当前全体共用同一模板。
func _idle_tree(in_labor: Labor) -> BehaviorTree:
	return IDLE_TREE

func _record_comes_first(in_a: TaskRecord, in_b: TaskRecord) -> bool:
	if in_a.task.priority != in_b.task.priority:
		return in_a.task.priority > in_b.task.priority
	return in_a.sequence < in_b.sequence
