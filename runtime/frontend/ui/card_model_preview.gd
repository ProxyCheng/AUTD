class_name CardModelPreview
extends Node3D

# 建筑卡片 SubViewport 内的 3D 预览取景器:模型就位后按整体 AABB 自动框正交相机,
# 避免为每种模型手调相机参数;挂在含模型实例的 model_renderer 上,相机由本脚本动态创建。

# 取景视线方向(世界系;模型中心沿该方向偏移放置相机)。
# 仰角偏高(约 55°):矮宽模型(料堆)以顶面/足迹为主,高仰角能让其占画面更大比重。
const EYE_DIR: Vector3 = Vector3(-0.65, 1.4, 0.75)
# 预留边距系数:>1 留白,<1 有意过取景裁掉 AABB 外圈空隙。
# 矮宽模型(如料堆)在竖版卡片里按宽度受限后上下留白大,需适度过取景才有体量感;
# 但不得小于堆体实际宽度对应的系数(≈0.73),否则会把模型本体裁出画面。
const MARGIN: float = 0.77

var _framed: bool = false

func _ready():
	_frame_camera.call_deferred()

func _frame_camera():
	if _framed:
		return
	await get_tree().process_frame
	var aabb := _collect_aabb(self)
	if aabb.size == Vector3.ZERO:
		return
	var center: Vector3 = aabb.get_center()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	camera.near = 0.05
	camera.far = 100
	camera.position = center + EYE_DIR.normalized()
	add_child(camera)
	camera.look_at_from_position(camera.position, center, Vector3.UP)
	# 视口宽高比由父级 SubViewport 决定;正交 size 以竖直半宽为单位
	var aspect: float = 1.0
	var viewport := _find_viewport()
	if viewport:
		aspect = float(viewport.size.x) / float(viewport.size.y)
	var half_x: float = 0
	var half_y: float = 0
	var pos: Vector3 = aabb.position
	var end: Vector3 = aabb.position + aabb.size
	for cx in [pos.x, end.x]:
		for cy in [pos.y, end.y]:
			for cz in [pos.z, end.z]:
				var rel: Vector3 = Vector3(cx, cy, cz) - center
				half_x = maxf(half_x, absf(rel.dot(camera.global_transform.basis.x)))
				half_y = maxf(half_y, absf(rel.dot(camera.global_transform.basis.y)))
	camera.size = maxf(half_y, half_x / aspect) * MARGIN
	_framed = true

func _collect_aabb(in_node: Node3D) -> AABB:
	var aabb: AABB = AABB()
	var first: bool = true
	for visual in in_node.find_children("*", "VisualInstance3D", true, false):
		var instance: VisualInstance3D = visual as VisualInstance3D
		var rel: Transform3D = in_node.global_transform.affine_inverse() * instance.global_transform
		var box: AABB = rel * instance.get_aabb()
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	return aabb

func _find_viewport() -> SubViewport:
	var parent: Node = get_parent()
	while parent:
		if parent is SubViewport:
			return parent
		parent = parent.get_parent()
	return null
