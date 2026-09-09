class_name CrossbowModel
extends Node3D

const ANIM_NAME: StringName = &"bone|boneAction_001"

# 备箭垛:显示在炮塔平台(随 %cog_top 水平转向)上的备用弩箭。
# 弦上那支由 %Arrow 负责(仅在非 idle 显示),本垛展示"弦下"的备箭,
# 数量 = backend 转发的 stored_count - 1。几何由 ItemStack 组件渲染(3×3=9 封顶)。
# 备箭垛在"模型真实单位(根空间)"下的落点锚点(垛底面中心)。
# 实测:八角形平台板(deck)顶面 y≈0.424,x∈[-0.386,0.388], z∈[-0.364,0.414];
# 中央机构(bracket)占 x∈[-0.155,0.165], z∈[-0.05,0.28],故净空区为后部( z<0 )。
# 锚点取平台面(y=0.424)后部右侧净空:整垛底边贴平台,避开中央机构。常量可微调。
const AMMO_ANCHOR: Vector3 = Vector3(0.22, 0.424, -0.20)

func _ready():
	# 播放器自带时钟不用,姿态完全由 progress 每帧采样决定。
	# 动画约定为单次"满弦→松弦",起点=满弦;换算见 set_progress。
	var animation: Animation = %AnimationPlayer.get_animation(ANIM_NAME)
	if animation:
		animation.loop_mode = Animation.LOOP_NONE
	# 保持"播放后暂停"的激活态:Godot 只在 active 时按 seek 刷新姿态,stop() 会失效
	%AnimationPlayer.play(ANIM_NAME)
	%AnimationPlayer.pause()
	%AnimationPlayer.seek(%AnimationPlayer.current_animation_length, true)
	# 初始处于 idle(空闲),箭默认隐藏,待 backend 状态落到非 idle 再显示
	%Arrow.visible = false
	_build_ammo_stack()

# 蓄力/待发/射击期间显示箭;仅 idle(空闲)隐藏。
# 弦上箭必须在"真的有一发装填"时才显示:非 idle 且备箭存量 > 0。
# 若弹药耗尽(stored_count=0,等待 logistics 补货),即使后端状态停在 ready/charging,
# 弦上也应无箭(备箭垛同步显示 0 支)。
var _show_arrow: bool = false
# 当前后端阶段(idle/charging/ready/firing),由 set_state 记录,供可见性重算
var _state: String = "idle"
# 逻辑装填在弦上的箭数(= stored_count);<=0 表示无箭可挂
var _loaded_count: int = 0

func set_state(in_state: String):
	# 状态只描述 backend 所处阶段(idle/charging/ready/firing);
	# 箭位置由 set_progress 驱动,此处只切可见性。
	_state = in_state
	_update_arrow_visibility()

func _update_arrow_visibility():
	# 弦上箭 = 弦上有货(非 idle)且弹药仓还有一支真正的主力
	_show_arrow = _state != "idle" and _loaded_count > 0
	%Arrow.visible = _show_arrow

func _apply_pose(in_time: float):
	# seek 需要激活态才刷新关键帧姿态:暂停中先 play 再 seek 再暂停
	if not %AnimationPlayer.is_playing():
		%AnimationPlayer.play(ANIM_NAME)
	%AnimationPlayer.seek(in_time, true)
	%AnimationPlayer.pause()

func set_progress(in_progress: float):
	# 归一化 progress → 动画时间:0=松弛(末尾)、1=满弦(起点)。
	# 蓄力(0→1)反向回弦,射击(firing 1→0)正向播完一发。
	# 若美术动画起止语义相反,把 seek 改为 in_progress * length 即可。
	var length: float = %AnimationPlayer.current_animation_length
	_apply_pose((1 - in_progress) * length)
	_update_arrow_position(in_progress)

# 箭位置 = 弦位点插值,参数即 progress:满弦(progress=1,弦拉紧)贴 PointB,
# 松弦(progress=0,弦放开)贴 PointA。蓄力 A→B 拉弦,发射 B→A 飞出。
# 三个节点为兄弟(同在 skin 下),用父空间局部坐标插值,避开骨架/皮肤变换。
func _update_arrow_position(in_progress: float):
	var t: float = in_progress if _show_arrow else 0.0
	%Arrow.position = %ArrowPointA.position.lerp(%ArrowPointB.position, t)

# 当前累计水平朝向角(弧度,不 wrap),跨 ±π 边界时靠 wrapf 平滑推进,避免 cog 部件瞬间反转。
var _current_yaw: float = 0.0

# 炮口水平朝向:由 backend 传入的 aim_direction(单位向量,y 为世界 z)决定。
# backend 已做限速,方向向量是逐帧连续变化的;这里把它累计成连续角度(不跳变)。
func set_aim_direction(in_direction: Vector3):
	# 模型 rest 朝 +Z(= Vector3.BACK),故取 atan2(x, z) 为朝向角
	var target_angle: float = atan2(in_direction.x, in_direction.z)
	var delta: float = wrapf(target_angle - _current_yaw, -PI, PI)
	_current_yaw += delta
	%cog_top.rotation.z = _current_yaw
	%cog_left.rotation.x = _current_yaw * 8 / 5
	%cog_right.rotation.x = -_current_yaw * 8 / 5

# 仅按目标距离调整俯仰;水平朝向改走 set_aim_direction。
func set_target_position(in_position: Vector3):
	var distance: float = global_position.distance_squared_to(in_position)
	var max_angle: float = 40 * PI / 180
	%body.rotation.x = max_angle * (1 - (distance - 1) / 5)

# —— 备箭垛(挂 %cog_top,随炮塔转向) ——

# ItemStack 组件实例
var _ammo_stack: ItemStack = null

# 在 %cog_top 下建备箭垛。%cog_top 深在 FBX 导入层(base 含 40 缩放 + 旋转),
# 直接用 root 空间的真实锚点经 base 逆变换写入其本地 transform,
# 使垛内以真实尺寸落在甲板顶面,并随炮塔水平转向。
func _build_ammo_stack():
	var cog_top: Node3D = %cog_top
	_ammo_stack = ItemStack.new()
	_ammo_stack.name = "AmmoStack"
	# 配置几何:3 支×3 层 = 9 支封顶;箭长轴略小,平放同向逐层摞
	_ammo_stack.per_row = 3
	_ammo_stack.layer_count = 3
	_ammo_stack.target_length = 0.35
	_ammo_stack.row_spacing = 1.05
	_ammo_stack.layer_spacing = 1.2
	# %cog_top 的父链是 root → base → cog_top(FBX 导入 base 含 40 缩放 + 旋转)。
	# 把"root 空间真实锚点"经整条父链逆变换,换算成 %cog_top 本地坐标;
	# 这样垛内以真实尺寸、真实方位落在锚点处,并随炮塔水平转向。
	var base: Node3D = get_node("base")
	var cog_top_local: Node3D = %cog_top
	var head: Transform3D = base.transform * cog_top_local.transform
	var real_anchor := Transform3D(Basis.IDENTITY, AMMO_ANCHOR)
	_ammo_stack.transform = head.affine_inverse() * real_anchor
	cog_top.add_child(_ammo_stack)
	_ammo_stack.set_item_type("arrow")
	_ammo_stack.set_count(0)

# BuildingActor 转发存量变化:备箭数 = stored_count - 1(弦上那支由 %Arrow 显示),
# 下限 0,上限 AMMO_STACK_SIZE。
func set_stored_count(in_count: int, in_capacity: int):
	_loaded_count = in_count
	if _ammo_stack:
		_ammo_stack.set_count(maxi(in_count - 1, 0))
	_update_arrow_visibility()
