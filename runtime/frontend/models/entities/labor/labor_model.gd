class_name LaborModel
extends Node3D

# 劳工表现:整身程序化动画。仓库内劳工 fbx 为静态模型(无骨骼/动画 clip),
# 因此在 state == "work"(顶岗驱动机器)时用轻量循环"劳作"动作表现——小幅前俯
# 起伏 + 轻微上下颠动;其余状态(含 idle/walk)复位为静止。将来接入带动作的美术
# 模型时,把这里的程序化动作替换成动画播放即可,state 契约不变。

const WORK_LEAN_AMPLITUDE: float = 0.05  # 前俯幅度(弧度,约 3°)
const WORK_BOB_AMPLITUDE: float = 0.02   # 上下颠动幅度(米)
const WORK_ANGULAR_SPEED: float = TAU * 2.2  # 劳作循环角速度(弧度/秒)

@onready var _body := $labor
var _body_base_transform: Transform3D
var _working: bool = false
var _work_time: float = 0.0

func _ready():
	if not _body:
		return
	_body_base_transform = _body.transform
	set_process(false)

func _process(in_delta: float):
	if not _working:
		return
	_work_time += in_delta
	var phase: float = _work_time * WORK_ANGULAR_SPEED
	_body.basis = _body_base_transform.basis.rotated(Vector3.RIGHT, sin(phase) * WORK_LEAN_AMPLITUDE)
	_body.position = _body_base_transform.origin + Vector3.UP * (maxf(sin(phase), 0.0) * WORK_BOB_AMPLITUDE)

func set_state(in_state: String):
	if in_state == "work":
		_working = true
		_work_time = 0.0
		set_process(true)
	elif _working:
		_working = false
		set_process(false)
		if _body:
			_body.transform = _body_base_transform
