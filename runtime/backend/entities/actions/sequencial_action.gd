extends CompositeAction
class_name SequencialAction

var next_index: int = 0
var current_action: Action = null

func enter():
	if get_child_count() == 0:
		return
	current_action = get_child(0)
	current_action.enter()

func tick(in_delta: float) -> float:
	var remained_time: float = in_delta
	while remained_time > 0:
		if not current_action:
			if next_index >= get_child_count():
				return remained_time
			current_action = get_child(next_index)
			next_index += 1
		current_action.enter()
		remained_time = current_action.tick(remained_time)
		if remained_time > 0:
			current_action.leave()
			current_action = null
	return remained_time
