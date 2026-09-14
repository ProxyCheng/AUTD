class_name CannonballBurst
extends Node3D

# 炮弹命中爆裂表现:一次性碎屑喷发 + 贴地冲击波环,把 backend 的区域伤害范围读出来。
# 由 RoomActor 在炮弹实体被移除时实例化到落点(Cannonball 命中即 _explode 后 remove_entity,
# 移除是炮弹唯一的消失路径),因此这里不新增任何 backend 信号/状态。
# 生命周期自管:碎屑寿命 + 余量后 queue_free,不常驻场景树、也不依赖 Timer 节点。

# 冲击波扩散时长(秒):短于碎屑寿命,先亮后灭,两个效果不互相盖住。
const SHOCKWAVE_DURATION: float = 0.35
# 冲击波起始缩放(相对最终区域半径):由小扩到实际半径,读作一圈向外推的冲击。
const SHOCKWAVE_START_RATIO: float = 0.55
# 冲击波自发光强度(与 building_actor.gd 的范围环边框同档,保证"发光"读感一致)。
const SHOCKWAVE_EMISSION_ENERGY: float = 1.5
# 自毁余量(秒):多留一点,保证最后一帧粒子渲染完再回收。
const LIFETIME_MARGIN: float = 0.2

@onready var _debris: GPUParticles3D = %debris
@onready var _shockwave: MeshInstance3D = %shockwave

func _ready():
	var lifetime: float = LIFETIME_MARGIN
	if _debris:
		lifetime += _debris.lifetime
		_debris.restart()
	if _shockwave:
		_play_shockwave()
	# 自毁:不用 Timer 节点,也不依赖外部回收(爆裂是一次性表现,无复用价值)。
	var free_tween: Tween = create_tween()
	free_tween.tween_interval(lifetime)
	free_tween.tween_callback(queue_free)

# 冲击波:环以半径 1.0 建模,只把 XZ 两轴缩放到 backend 的区域半径(单一事实来源,不抄第二份数值),
# 同时把 alpha 淡出到 0;y 轴不缩放,环保持贴地。
func _play_shockwave():
	var material: StandardMaterial3D = _shockwave.material_override as StandardMaterial3D
	if material:
		# 子资源在场景实例间共享:复制一份再改 alpha,否则先爆的一发会把共享材质淡成全透明,
		# 后续爆裂的环就看不见了。
		material = material.duplicate()
		_shockwave.material_override = material
		# 本机引擎的场景序列化会丢掉 StandardMaterial3D 的 emission 标志(实测:手写 .tscn 后
		# 编辑器重存即丢失),故自发光在运行时补上 —— 同 building_actor.gd 的程序化范围环;
		# 颜色取底色,避免橙色的第二份数值。
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = SHOCKWAVE_EMISSION_ENERGY
	var target_scale: Vector3 = Vector3(Cannonball.AREA_RADIUS, 1.0, Cannonball.AREA_RADIUS)
	# 只缩 XZ,y 恒为 1:环的管径不被压扁,始终贴地。
	_shockwave.scale = Vector3(target_scale.x * SHOCKWAVE_START_RATIO, 1.0, target_scale.z * SHOCKWAVE_START_RATIO)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_shockwave, "scale", target_scale, SHOCKWAVE_DURATION)
	if material:
		tween.tween_property(material, "albedo_color:a", 0.0, SHOCKWAVE_DURATION)
