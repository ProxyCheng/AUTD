class_name CannonballModel
extends ArrowModel

# 炮弹表现模型:与弩箭共用同一套弹道表现(抛物线抬升 + 沿切线俯仰),故直接继承 ArrowModel
# —— 其 set_flight/set_state 由 EntityActor 按 has_method 探测调用,无需重写。
# 弹道公式本体仍在 backend(Arrow.arc_slope / Arrow.launch_pitch / Arrow.GRAVITY),前后端同源。
# 若日后炮弹需要独立表现(自转、拖尾、命中特效),在此覆写对应方法即可。

@onready var _trail: GPUParticles3D = %trail

# EntityActor 会给模型根套上 EntityActor.MODEL_SCALE 的统一缩放(见 entity_actor.gd),
# 尾迹粒子(尺寸/速度)也会被一起缩小;这里反向缩放抵消(直接引用常量,不写死 3.333),
# 让烟迹按世界尺度渲染,不随模型缩放走样。
func _ready():
	if _trail:
		_trail.scale = Vector3.ONE / EntityActor.MODEL_SCALE

# 尾迹只在飞行途中喷:进度到 1(=落点)即停。
# 不能靠场景默认 emitting=true —— 同一个 cannonball.tscn 也被 ItemStack 当"物品道具"实例化
# (火炮备弹垛 / 打造车间产出垛),静止的道具会一直冒烟;编辑器视口同理。
# 这里由 set_flight 驱动(飞行中每帧经 EntityActor 转发),静止实例永远收不到该调用,故不喷。
func set_flight(in_progress: float, in_direction: Vector2, in_launch_height: float, in_flight_time: float, in_move_speed: float):
	super.set_flight(in_progress, in_direction, in_launch_height, in_flight_time, in_move_speed)
	if _trail:
		_trail.emitting = in_progress < 1.0
