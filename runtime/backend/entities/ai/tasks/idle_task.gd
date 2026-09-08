class_name IdleTask
extends BTAction

# 待机叶子:把实体置为 idle 状态并保持 RUNNING。
# duration < 0 表示无限待机;>= 0 时跑满该秒数后 SUCCESS(固定短 tick 下即固定次数)。

@export var duration: float = -1

func _enter():
	var entity := get_agent() as Entity
	if entity:
		entity.state = "idle"

func _tick(_in_delta: float) -> int:
	if duration >= 0 and get_elapsed_time() >= duration:
		return BT.Status.SUCCESS
	return BT.Status.RUNNING
