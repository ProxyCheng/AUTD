class_name WanderTask
extends BTAction

# 待机游荡叶子:工人无事可做时在出生锚点附近随机游走,走走停停。
# 每段随机目标 = 锚点 + 半径内随机偏移;到达后停歇一段随机时长再走。
# 移动复用与 MoveToTargetTask 相同的直线 move_toward 语义(无寻路网格,固定短 tick)。
#
# 游荡 duration 秒后返回 SUCCESS,把控制权交还 idle.tres 外层的 BTRepeat —— 这是**必须**的:
# 空闲树每轮的第一项是卸货判定(FindDepositBagTask),若本叶恒 RUNNING,BTRepeat 就永不迭代,
# 工人会带着"当时还需要、后来用不上"的工具一直游荡下去(见 FindDepositBagTask 按
# Tool.unused_time / is_unused_too_long() 的判定)。让出后下一轮重跑卸货判定,用不上的工具
# 就会被卸进仓里。
# 锚点存黑板而非实例字段:工人从任务树回到空闲树时,空闲树会被重新 instantiate,本叶是全新
# 实例,锚点若只存实例字段,每次回到空闲都会以当前位置为锚,工人会随机游走越走越远;
# 只有工人真的换了地方(离锚点超过 ANCHOR_KEEP_RANGE)才重取锚点。

const BB_ANCHOR: StringName = &"wander_anchor"
# 锚点保留阈值:离锚点超过它才认为工人换了地方(取约两倍游荡半径,避免在锚点附近误判)。
const ANCHOR_KEEP_RANGE: float = 6.0

@export_range(0.0, 10.0) var radius: float = 3.0
@export_range(0.0, 5.0) var rest_min: float = 0.8
@export_range(0.0, 5.0) var rest_max: float = 2.5
# 一次游荡持续多久后让出(返回 SUCCESS 交还外层 BTRepeat,让下一轮重跑卸货判定)。
@export_range(1.0, 60.0) var duration: float = 6.0

var _anchor: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _rest_timer: float = 0.0
var _elapsed: float = 0.0

func _enter():
	var agent := get_agent() as Entity
	if not agent:
		return
	var bb := get_blackboard()
	var stored: Variant = bb.get_var(BB_ANCHOR, null, false)
	# 顺序:先判类型再取值,避免把黑板里别的残留当锚点用。
	if stored is Vector2 and agent.position.distance_to(stored) < ANCHOR_KEEP_RANGE:
		_anchor = stored
	else:
		_anchor = agent.position
		bb.set_var(BB_ANCHOR, _anchor)
	_target = agent.position
	_rest_timer = randf_range(rest_min, rest_max)
	_elapsed = 0.0

func _tick(in_delta: float) -> int:
	var agent := get_agent() as Entity
	if not agent:
		return BT.Status.FAILURE
	_elapsed += in_delta
	if _elapsed >= duration:
		# 让出:SUCCESS 交还外层 BTRepeat,下一轮从头重跑卸货判定。
		return BT.Status.SUCCESS
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
