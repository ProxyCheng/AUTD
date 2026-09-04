extends Action
class_name IdleAction

var wait_time: float = -1

func _init(in_wait_time: float = -1):
	super()._init()
	wait_time = in_wait_time

func tick(in_delta: float) -> ActionStatus:
	if wait_time < 0:
		return ActionStatus.running()
	if in_delta < wait_time:
		wait_time -= in_delta
		return ActionStatus.running()
	var remained_time = in_delta - wait_time
	wait_time = 0
	return ActionStatus.success(remained_time)
