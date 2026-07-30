extends Action
class_name IdleAction

var wait_time: float = -1

func _init(in_wait_time: float = -1):
	wait_time = in_wait_time

func tick(in_delta: float) -> float:
	if wait_time < 0:
		return 0
	if in_delta < wait_time:
		wait_time -= in_delta
		return 0
	var remained_time = in_delta - wait_time
	wait_time = 0
	return remained_time
