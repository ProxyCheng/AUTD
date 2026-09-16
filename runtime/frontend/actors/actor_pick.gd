class_name ActorPick
extends RefCounted

# 点击宽容度(米):包围盒外扩量,小模型(如工人)也能点中。
const PICK_MARGIN: float = 0.12

# 世界空间射线 vs actor 本地包围盒(外扩 PICK_MARGIN)的 slab 测试,返回进入距离;未命中 -1。
# actor 自身无缩放(缩放只在 model 子节点上),故 actor 本地空间的 t 即世界尺度。
# tmin 从 0 起算 → 相机背后的命中被拒;包围盒为空(无网格)则不可点。
static func hit_distance(
		in_origin: Vector3,
		in_direction: Vector3,
		in_box: AABB,
		in_global_transform: Transform3D) -> float:
	if in_box.size == Vector3.ZERO or in_direction.is_zero_approx():
		return -1.0
	var box: AABB = in_box.grow(PICK_MARGIN)
	var to_local: Transform3D = in_global_transform.affine_inverse()
	var local_origin: Vector3 = to_local * in_origin
	var local_direction: Vector3 = to_local.basis * in_direction
	var tmin: float = 0.0
	var tmax: float = INF
	for axis: int in 3:
		var origin_axis: float = local_origin[axis]
		var direction_axis: float = local_direction[axis]
		if absf(direction_axis) < 0.000001:
			# 射线平行于该轴:原点在板外则永不相交
			if origin_axis < box.position[axis] or origin_axis > box.end[axis]:
				return -1.0
			continue
		var t1: float = (box.position[axis] - origin_axis) / direction_axis
		var t2: float = (box.end[axis] - origin_axis) / direction_axis
		if t1 > t2:
			var swap: float = t1
			t1 = t2
			t2 = swap
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	return tmin
