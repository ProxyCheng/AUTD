class_name Workshop
extends Building

# 需要工人驱动的机器基类(如弩炮、作坊)。基类负责"无人时自动补员 + 值守心跳 +
# 注入驱动量 + 完成一次生产后放工人离岗"这一整套通用生命周期,子类只需描述自身机器语义。
#
# 生命周期:机器在 _needs_worker() 为真且无人值守时,向 LaborManager 注册一个
# ManBuildingTask(required_count=1):派一名工人沿行为树走到岗位点(work_entry_position),
# 每 tick 由 ProvideWorkloadTask 调 work(in_workload) 注入驱动量;注入同时维护"有人值守"
# 窗口(_manned_timer)。直到 is_work_done() 判定本轮一次生产完成,工人离岗归还调度池,
# 机器随后按 _needs_worker() 再次补位。无人值守期间机器表现(是否停摆)由子类决定。
#
# 子类钩子(按需覆盖):
#   _needs_worker() -> bool   是否需要顶岗工人(如弩炮未满弦/有待产订单;默认 false)
#   is_work_done()  -> bool    本轮一次生产是否已完成(完成即释放工人;默认 false)
#   _tick_machine(in_delta)   机器每帧推进(基类 tick 先做值守维护再调它;默认空)
#   _apply_workload(amount)   把注入的驱动量换算成自身进度/状态(默认空)
#   _reset_shift()            新一轮值岗(工人更替后首次注入)开始时的复位(默认空)
#   work_entry_position()     岗位点(默认 = 自身格子 + WORK_ENTRY_OFFSET)
# 不要覆盖 tick()/work() —— 通用生命周期已在基类实现,需要机器帧推进请实现 _tick_machine。

# 有人值守判定窗口:超过该时长无 work() 注入即视为无人,机器可据此停摆
const MANNED_TIMEOUT: float = 0.2
# 岗位点相对机器格子的固定偏移(方向/大小按模型微调;不同机器可在 work_entry_position 覆写)
const WORK_ENTRY_OFFSET: Vector2 = Vector2(0.4, 0.4)

var required_workers: int = 1
var workers: Array = []
var manning_task: ManBuildingTask = null
var _worker_requested: bool = false
var _manned_timer: float = 0  # >0 表示有人值守(近期有工人注入 work())

func _exit_tree():
	_cancel_worker_request()

# 机器主循环:先做值守/补员维护,再交子类推进机器自身逻辑。
func tick(in_delta: float):
	_manned_timer = maxf(_manned_timer - in_delta, 0)
	_maintain_manning()
	_tick_machine(in_delta)

# —— 工人驱动入口(由 ProvideWorkloadTask 每 tick 调用,勿由子类覆盖)——
func work(in_workload: float):
	var was_unmanned := not _is_manned()
	_manned_timer = MANNED_TIMEOUT
	if was_unmanned:
		_reset_shift()
	_apply_workload(in_workload)

func is_work_done() -> bool:
	return false

func _needs_worker() -> bool:
	return false

func _is_manned() -> bool:
	return _manned_timer > 0

# 岗位点:机器所在格子的固定角(相对自身坐标 WORK_ENTRY_OFFSET),贴机器且不重叠。
func work_entry_position() -> Vector2:
	return Vector2(axis) + WORK_ENTRY_OFFSET

# 子类钩子:值岗生命周期 / 机器推进

func _reset_shift():
	pass

func _apply_workload(in_workload: float):
	pass

func _tick_machine(in_delta: float):
	pass

# 该机器顶岗任务的调度优先级(子类可覆盖;攻击建筑如 Crossbow 设为更高档,
# 保证驱动机器产出的任务不被普通物流挤占)。默认=生产 10。
func manning_priority() -> int:
	return 10

# —— 补员调度 ——

func _get_manager() -> LaborManager:
	if not Level.current:
		return null
	return Level.current.labor_manager

# 每帧按需维护:无人且机器需要工人、且没有在途请求时,注册一个顶岗任务。
# 任务在 is_work_done()(射出一发/产出一件)后完成,或工人流失被取消;
# 任务节点被释放后自动补位(LaborManager 派最近空闲工人,通常仍是刚离岗、守在岗位旁的那位)。
func _maintain_manning():
	if not is_inside_tree():
		return
	var manager := _get_manager()
	if not manager:
		return
	if _worker_requested:
		if manning_task and is_instance_valid(manning_task):
			return
		_worker_requested = false
	if not _is_manned() and _needs_worker():
		_worker_requested = true
		manning_task = ManBuildingTask.new(self, work_entry_position(), 1, manning_priority())
		manager.register_task(manning_task)

func _cancel_worker_request():
	_worker_requested = false
	var manager := _get_manager()
	if is_instance_valid(manager) and manning_task and is_instance_valid(manning_task):
		manager.cancel_task(manning_task)
	manning_task = null
