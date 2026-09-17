extends SceneTree

# Trs(世界空间 TRS 插值)测试。
#
#   <godot.exe> --path <项目根> --headless --script res://test/trs_test.gd
#
# 退出码 = 失败项数(0 = 全过)。
#
# 回归背景:Transform3D.interpolate_with() 内部用 basis.get_rotation_quaternion() 取朝向,
# 而它第一步是 orthonormalized() —— 端点缩放为 0 时零基既归一化不出朝向(引擎直接报
# "must be normalized in order to be casted to a Quaternion"),整段插值随之报废。本项目要用
# "缩放 0"的端点表达"缩到无 / 从无到有"(见 ItemFlight),故 Trs.lerp 把平移/朝向/缩放拆开算。
# 本测试锁两件事:
#   ① 正常端点下与 interpolate_with 逐元素一致 —— 抽公共方法不能与引擎行为分叉;
#   ② 退化端点下不出 NaN、不报错,缩放照常插到 0,朝向沿用另一端(不翻面)。
#
# 比较一律用 Transform3D.is_equal_approx / is_finite:Quaternion.angle_to 走 acos,
# 夹角接近 0 时对浮点噪声极敏感(点积差 1e-7 就能报出约 4e-4 弧度的"夹角"),
# 拿它当容差判据会把纯噪声判成真差异。

const EPSILON: float = 0.0001

func _init():
	var failed: int = 0

	# —— ① 正常端点:三样都插值,且与引擎 interpolate_with 逐元素一致 ——
	var from_pose := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5), Vector3.ZERO)
	var to_pose := Transform3D(
			Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)).scaled(Vector3.ONE * 2.0),
			Vector3(4, 0, 2))
	for k: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var got: Transform3D = Trs.lerp(from_pose, to_pose, k)
		var want: Transform3D = from_pose.interpolate_with(to_pose, k)
		var same: bool = got.is_equal_approx(want)
		print("PARITY k=", k, " equal=", same, " origin=", got.origin, " scale=", got.basis.get_scale())
		if not same:
			failed += 1

	# 中点应确实各走一半:位置 (2,0,1)、缩放 1.25、偏航 45°
	var mid: Transform3D = Trs.lerp(from_pose, to_pose, 0.5)
	var mid_yaw: float = rad_to_deg(mid.basis.get_euler().y)
	print("MID origin=", mid.origin, " scale=", mid.basis.get_scale(), " yaw_deg=", mid_yaw)
	if mid.origin.distance_to(Vector3(2, 0, 1)) > EPSILON:
		failed += 1
	if absf(mid.basis.get_scale().x - 1.25) > EPSILON:
		failed += 1
	if absf(mid_yaw - 45.0) > 0.01:
		failed += 1

	# —— ② 终点退化(缩到无) ——
	var vanish: Transform3D = Trs.zero_scale(Vector3(6, 0, 3))
	print("ZERO_SCALE valid=", Trs.is_pose_valid(vanish), " finite=", vanish.is_finite())
	if Trs.is_pose_valid(vanish) or not vanish.is_finite():
		failed += 1
	for k: float in [0.0, 0.5, 1.0]:
		var got: Transform3D = Trs.lerp(from_pose, vanish, k)
		print("SHRINK k=", k, " origin=", got.origin, " scale=", got.basis.get_scale(),
				" finite=", got.is_finite())
		if not got.is_finite():
			failed += 1
	# 终点必须真的缩到 0
	if Trs.lerp(from_pose, vanish, 1.0).basis.get_scale().length() > EPSILON:
		failed += 1
	# 朝向沿用起点(退化端借另一端):中途朝向应与起点一致,不该翻面
	var shrink_mid: Transform3D = Trs.lerp(from_pose, vanish, 0.5)
	var rot_held: bool = shrink_mid.basis.orthonormalized().is_equal_approx(from_pose.basis.orthonormalized())
	var shrink_scale: float = shrink_mid.basis.get_scale().x
	print("SHRINK mid rotation_held=", rot_held, " scale=", shrink_scale)
	if not rot_held:
		failed += 1
	# 缩放确实在往 0 走(0 < 中点 < 起点)
	if shrink_scale <= 0.0 or shrink_scale >= from_pose.basis.get_scale().x:
		failed += 1

	# —— ③ 起点退化(从无到有):同样不能出 NaN ——
	var born: Transform3D = Trs.lerp(Trs.zero_scale(Vector3.ZERO), to_pose, 0.5)
	print("GROW mid origin=", born.origin, " scale=", born.basis.get_scale(), " finite=", born.is_finite())
	if not born.is_finite():
		failed += 1
	if born.basis.get_scale().length() < EPSILON:
		failed += 1

	# —— ④ 权重越界自行夹取 ——
	var under: bool = Trs.lerp(from_pose, to_pose, -1.0).is_equal_approx(from_pose)
	var over: bool = Trs.lerp(from_pose, to_pose, 2.0).is_equal_approx(to_pose)
	print("CLAMP under=", under, " over=", over)
	if not under or not over:
		failed += 1

	print("RESULT failed=", failed)
	quit(failed)
