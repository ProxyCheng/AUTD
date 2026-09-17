class_name Trs
extends RefCounted

# 世界空间 TRS 插值(平移 + 朝向 + 缩放三样一起过渡)的**唯一实现**,供各处直接调用。
#
# 为什么不直接用 Transform3D.interpolate_with:它内部靠 basis.get_rotation_quaternion() 取朝向,
# 而该方法第一步是 orthonormalized() —— 端点缩放为 0 时零基正交归一化会算出 NaN,整段插值
# (位置也一起)随之报废。本项目恰恰要用"缩放为 0"的端点表达"缩到无 / 从无到有"(见 ItemFlight),
# 故这里把三样拆开算:朝向走四元数 slerp(缩放为 0 也不影响它)、缩放走 Vector3 lerp、位置走 lerp。
#
# 除退化端点外,结果与 interpolate_with 一致:引擎的 set_quaternion_scale(q, s) 就是 R * S,
# 与 get_scale() 声明的 M = R.S 配套;这里用 Basis(q) * Basis.from_scale(s) 复现同一套约定
# (注意不是 Basis.scaled(),那是 S * R,非等比缩放时会与 get_scale() 对不上)。

# 缩放退化阈值(各轴长度):任一轴小于它即视为该轴缩放为 0 —— 该端朝向不可解。
const SCALE_EPSILON: float = 0.0001

# 把 in_from 插值到 in_to,in_weight ∈ [0,1](越界自行夹取)。
# 端点姿态退化(缩放为 0)时它给不出朝向,改用另一端的朝向 —— 于是插值期间朝向恒定,
# 不会出现"转到一半突然翻面";两端都退化才退回单位朝向。
static func lerp(in_from: Transform3D, in_to: Transform3D, in_weight: float) -> Transform3D:
	var weight: float = clampf(in_weight, 0.0, 1.0)
	var from_valid: bool = is_pose_valid(in_from)
	var to_valid: bool = is_pose_valid(in_to)
	var from_rotation: Quaternion = in_from.basis.get_rotation_quaternion() if from_valid else Quaternion.IDENTITY
	var to_rotation: Quaternion = in_to.basis.get_rotation_quaternion() if to_valid else Quaternion.IDENTITY
	if not from_valid:
		from_rotation = to_rotation
	if not to_valid:
		to_rotation = from_rotation
	var rotation: Quaternion = from_rotation.slerp(to_rotation, weight)
	var scale: Vector3 = in_from.basis.get_scale().lerp(in_to.basis.get_scale(), weight)
	return Transform3D(Basis(rotation) * Basis.from_scale(scale), in_from.origin.lerp(in_to.origin, weight))

# 该姿态的缩放是否可解出朝向:任一轴长度小于阈值即视为退化(见 SCALE_EPSILON)。
static func is_pose_valid(in_pose: Transform3D) -> bool:
	var s: Vector3 = in_pose.basis.get_scale()
	return minf(absf(s.x), minf(absf(s.y), absf(s.z))) > SCALE_EPSILON

# 造一个"没有尺寸"的姿态:位置给定,朝向单位朝向,缩放为 0。
# 作 lerp 的终点读作"缩到无",作起点读作"从无到有"。调用方不必自己拼零基 ——
# 零基的朝向本就不可解,由 lerp 自行借另一端,这里给什么都不影响结果。
static func zero_scale(in_at: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), in_at)
