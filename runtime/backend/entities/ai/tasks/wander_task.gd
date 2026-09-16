class_name WanderTask
extends BTAction

# 待机游荡叶子:工人无事可做时在出生锚点附近随机游走,走走停停。
# 每段随机目标 = 锚点 + 半径内随机偏移;到达后停歇一段随机时长再走。
# 移动复用与 MoveToTargetTask 相同的直线 move_toward 语义(无寻路网格,固定短 tick)。
# 锚点取实体进入本树时的位置(即工人空闲时所在处),避免越走越远。

@export_range(0.0, 10.0) var radius: float = 3.0
@export_range(0.0, 5.0) var rest_min: float = 0.8
@export_range(0.0, 5.0) var rest_max: float = 2.5

var _anchor: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _rest_timer: float = 0.0

func _enter():
	var agent := get_agent() as Entity
	if not agent:
		return
	_anchor = agent.position
	_target = agent.position
	_rest_timer = randf_range(rest_min, rest_max)

func _tick(in_delta: float) -> int:
	var agent := get_agent() as Entity
	if not agent:
		return BT.Status.FAILURE
	if _rest_timer > 0:
		agent.state = "idle"
		_rest_timer -= in_delta
		if _rest_timer > 0:
			return BT.Status.RUNNING
		_pick_target()
	var distance := agent.position.distance_to(_target)
	var step := agent.get_move_speed() * in_delta
	if step >= distance:
		agent.position = _target
		_rest_timer = randf_range(rest_min, rest_max)
		return BT.Status.RUNNING
	agent.position = agent.position.move_toward(_target, step)
	agent.direction = (_target - agent.position).normalized()
	agent.state = "walk"
	return BT.Status.RUNNING

func _pick_target():
	var agent := get_agent() as Entity
	var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if offset.length() > 1.0:
		offset = offset.normalized()
	_target = _anchor + offset * randf_range(0.0, radius)
	if not agent:
		return
	agent.direction = (_target - agent.position).normalized()
