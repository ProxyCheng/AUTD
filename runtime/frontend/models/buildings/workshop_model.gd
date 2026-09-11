class_name WorkshopModel
extends Node3D

# 作坊类建筑模型的公共工作动画:机器运转时整机来回压扁(变矮变宽)↔ 恢复,
# 停机时平滑复位。只动美术网格(不碰 ItemStack 内容垛),由 BuildingActor 经
# set_state(building.state) 驱动(见 Workshop._tick_machine:state = "working"/"idle")。

# 最大压扁幅度(Y 轴收缩比例)
const WORK_SQUASH: float = 0.12
# 最大变宽幅度(XZ 轴扩张比例;约取压扁的一半,近似保体积)
const WORK_WIDEN: float = 0.06
# 起伏角速度(弧度/秒)
const WORK_SPEED: float = 6.0
# 停机复位速度(每秒插值比例)
const RESTORE_SPEED: float = 10.0

# 是否处于运转态
var _working: bool = false
# 起伏相位
var _phase: float = 0.0
# 美术网格节点(模型根下除 ItemStack 外的首个 Node3D 子节点)
var _mesh: Node3D = null
# 美术网格原始缩放(场景配置,动画在其基础上叠加)
var _mesh_base_scale: Vector3 = Vector3.ONE

func _ready():
	_mesh = _find_mesh()
	if _mesh:
		_mesh_base_scale = _mesh.scale

# 取美术网格:模型根下首个非 ItemStack 的 Node3D 子节点。
func _find_mesh() -> Node3D:
	for child in get_children():
		if child is Node3D and not (child is ItemStack):
			return child
	return null

# BuildingActor 转发 backend state:working 时开启起伏动画,其余状态平滑复位。
func set_state(in_state: String):
	_working = in_state == "working"

func _process(in_delta: float):
	if not _mesh:
		return
	if _working:
		_phase += in_delta * WORK_SPEED
		var k: float = 0.5 + 0.5 * sin(_phase)
		_mesh.scale = _mesh_base_scale * Vector3(
			1.0 + WORK_WIDEN * k, 1.0 - WORK_SQUASH * k, 1.0 + WORK_WIDEN * k)
	elif not _mesh.scale.is_equal_approx(_mesh_base_scale):
		_mesh.scale = _mesh.scale.lerp(_mesh_base_scale, clampf(in_delta * RESTORE_SPEED, 0.0, 1.0))
