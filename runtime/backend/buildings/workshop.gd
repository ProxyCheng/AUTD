class_name Workshop
extends Building

var required_workers: int = 1
var workers: Array = []

func work(in_workload: float):
	pass

# 一次生产是否已完成(如弩炮射出一发、作坊下线一件产物)。完成时顶岗工人离岗。
func is_work_done() -> bool:
	return false
