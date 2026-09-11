class_name WorkshopModel
extends Node3D

# 生产建筑模型的公共"干活"动画基类:
#   - 仅当 backend state == "working"(有人值守、正在产出)时播放,停机平滑复位;
#   - 动画作用于美术网格(模型根下除 ItemStack 外的首个 Node3D 子节点),叠加在其
#     场景变换之上;ItemStack 内容垛不受影响;
#   - 具体动作由子类覆写 _animate_work 定制(默认:平滑压扁↔恢复)。
# 由 BuildingActor 经 set_state(building.state) 驱动(见 Workshop._tick_machine)。

# 停机复位速度(每秒插值比例)
const RESTORE_SPEED: float = 10.0

var _working: bool = false
# 运转累计秒数(子类据此做周期性动作;每次进入运转归零)
var _phase: float = 0.0
var _mesh: Node3D = null
var _mesh_base_scale: Vector3 = Vector3.ONE
var _mesh_base_position: Vector3 = Vector3.ZERO

func _ready():
	_mesh = _find_mesh()
	if _mesh:
		_mesh_base_scale = _mesh.scale
		_mesh_base_position = _mesh.position

# 取美术网格:模型根下首个非 ItemStack 的 Node3D 子节点。
func _find_mesh() -> Node3D:
	for child in get_children():
		if child is Node3D and not (child is ItemStack):
			return child
	return null

# BuildingActor 转发 backend state:仅 "working" 时播放,其余状态平滑复位。
func set_state(in_state: String):
	_working = in_state == "working"
	if _working:
		_phase = 0.0

func _process(in_delta: float):
	if not _mesh:
		return
	if _working:
		_phase += in_delta
		_animate_work(in_delta)
	else:
		_restore(in_delta)

# 运转时的整机姿态(子类覆写)。默认:平滑压扁↔恢复。
func _animate_work(_in_delta: float):
	var k: float = 0.5 + 0.5 * sin(_phase * 6.0)
	_squash(k, 0.12, 0.06)

# 把 k∈[0,1] 映射为"变矮变宽"的整机缩放(k=0 原状,k=1 最扁)。
func _squash(in_k: float, in_squash: float, in_widen: float):
	_mesh.scale = _mesh_base_scale * Vector3(
		1.0 + in_widen * in_k, 1.0 - in_squash * in_k, 1.0 + in_widen * in_k)

# 在原始位置基础上平移美术网格(用于摇晃/下沉)。
func _shift(in_offset: Vector3):
	_mesh.position = _mesh_base_position + in_offset

# 停机:平滑回到原始变换。
func _restore(in_delta: float):
	if _mesh.scale.is_equal_approx(_mesh_base_scale) and _mesh.position.is_equal_approx(_mesh_base_position):
		return
	var f: float = clampf(in_delta * RESTORE_SPEED, 0.0, 1.0)
	_mesh.scale = _mesh.scale.lerp(_mesh_base_scale, f)
	_mesh.position = _mesh.position.lerp(_mesh_base_position, f)
