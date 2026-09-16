class_name LaborModel
extends Node3D

# 劳工表现:整身程序化动画。仓库内劳工 fbx 为静态模型(无骨骼/动画 clip),
# 因此在 state == "work"(顶岗驱动机器)时用轻量循环"劳作"动作表现——小幅前俯
# 起伏 + 轻微上下颠动;其余状态(含 idle/walk)复位为静止。将来接入带动作的美术
# 模型时,把这里的程序化动作替换成动画播放即可,state 契约不变。
# 劳作时另从额头喷洒 %sweat 汗滴粒子,非劳作状态关闭(见 _setup_sweat / set_state)。

const WORK_LEAN_AMPLITUDE: float = 0.05  # 前俯幅度(弧度,约 3°)
const WORK_BOB_AMPLITUDE: float = 0.02   # 上下颠动幅度(米)
const WORK_ANGULAR_SPEED: float = TAU * 2.2  # 劳作循环角速度(弧度/秒)
# 汗滴发射点:额头 ≈ 模型包围盒顶面往下 10% 身高(按实测 AABB 比例换算,不写死身高)
const SWEAT_HEAD_TOP_RATIO: float = 0.10

@onready var _body: Node3D = $labor
@onready var _sweat: GPUParticles3D = %sweat
var _body_base_transform: Transform3D
var _working: bool = false
var _work_time: float = 0.0

# 手持工具挂点:劳作动画(前俯 + 颠动)作用在 $labor 上,工具必须挂在这下面才会跟着
# 身体一起晃。EntityActor 用 has_method 探测本方法(§6 模型哑脚本约定),
# 没有它的模型(如史莱姆)工具退回挂在 actor 根上。
func tool_mount() -> Node3D:
	return _body

func _ready():
	_setup_sweat()
	if not _body:
		return
	_body_base_transform = _body.transform
	set_process(false)

# 汗滴初始化:发射点/缩放不依赖 $labor,故先于 _ready 的早退执行,模型缺件时也生效。
# 发射点由实测 AABB 推算(额头),美术改身高时自动跟随;框为空(无网格)则保持原位。
func _setup_sweat():
	if not _sweat:
		return
	# EntityActor 会给模型根套 MODEL_SCALE 统一缩放,粒子尺寸/速度会被一起缩小;
	# 反向缩放抵消(引用常量,不写死 3.333),让汗滴按世界尺度渲染(同 cannonball 尾迹)。
	_sweat.scale = Vector3.ONE / EntityActor.MODEL_SCALE
	var box := HeadBar.measure_box(self, self)
	if box.size == Vector3.ZERO:
		return
	var center := box.get_center()
	_sweat.position = Vector3(center.x, box.end.y - box.size.y * SWEAT_HEAD_TOP_RATIO, center.z)

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
		if _sweat:
			_sweat.emitting = true
	elif _working:
		_working = false
		set_process(false)
		if _body:
			_body.transform = _body_base_transform
		if _sweat:
			_sweat.emitting = false
