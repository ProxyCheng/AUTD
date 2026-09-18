class_name ConveyorModel
extends Node3D

# 传送带表现模型(哑表现脚本,不接 backend 逻辑)。
#
# 带面运动由骨架循环动画驱动:24 根横条合并成单个蒙皮网格,一根横条一根骨
# (见 conveyor.blend 的 ConveyorRig / cleats),动画 ConveyorRig|Run 由
# %AnimationPlayer 播放。
#
# 循环机制:一个动画周期恰好走过"一个横条间距",跑完一圈后每根横条正好落在
# 下一根的位置;24 根完全同构 ⇒ 姿态集合重合 ⇒ 无缝循环,且关键帧量只有
# "跑满整圈"方案的 1/24。故本动画必须整体循环播放,不能当单次动作播。
#
# 尺度:conveyor.tscn 的根节点把美术缩到 1 格(带面长 1 单位),所以带面的世界线
# 速度要乘上根节点缩放。这里用自身 scale 推算,避免与场景里的缩放两处硬编码脱节。
#
# 朝向:根节点同时绕 Y 转 +90°,把带面行进方向(模型 +X)对到模型正面(-Z),
# 与 BuildingActor.look_at 的约定一致 —— 于是 data.direction 就是输出方向。
#
# 节点约定(见 conveyor.tscn,%AnimationPlayer 已在场景内标 unique_name_in_owner):
#   %AnimationPlayer → ConveyorRig|Run

const ANIM_NAME: StringName = &"ConveyorRig|Run"

# 动画一个周期的时长(秒):Blender 侧 12 帧 @24fps。
const CYCLE_SECONDS: float = 0.5

# 一个周期内带面在"模型自身空间"走过的距离(m):24 根横条等分环路后的间距。
const CYCLE_DISTANCE: float = 0.171062

# 动画在模型自身空间里的基准带面线速度(m/s),即 speed_scale = 1 时的速度。
const ANIM_BASE_SPEED: float = CYCLE_DISTANCE / CYCLE_SECONDS

# 默认带面线速度(m/s,世界空间):与 backend Conveyor.CELL_TRAVEL_SECONDS 对齐
# (一格 1 单位 / 1.0 秒)。后端改了那个常量,这里要跟着改。
const DEFAULT_SPEED: float = 1.0

# 唯一名解析的播放器:FBX 自带,已由 conveyor.tscn 标为 unique_name_in_owner。
@onready var _animation: AnimationPlayer = %AnimationPlayer

func _ready():
	# 首尾姿态集合相接(见文件头"循环机制"),故用 LOOP_LINEAR 整体循环。
	var animation: Animation = _animation.get_animation(ANIM_NAME)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR
	set_speed(DEFAULT_SPEED)

# 设置带面线速度(m/s,世界空间):按世界空间基准速度换算成播放速率;
# 传 0 则暂停(横条停在原地)。
# 由建筑 Actor 经 has_method 探测调用(可选表现接口,同 §5.4 的 state 契约)。
func set_speed(in_speed: float):
	_animation.speed_scale = in_speed / _world_base_speed()
	if is_zero_approx(in_speed):
		_animation.pause()
	elif not _animation.is_playing():
		_animation.play(ANIM_NAME)

# 世界空间基准带面速度:动画自身空间的速度 × 根节点缩放(本场景把美术缩到 1 格)。
func _world_base_speed() -> float:
	return ANIM_BASE_SPEED * absf(scale.x)
