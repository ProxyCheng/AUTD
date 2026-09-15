class_name Mode
extends Node

# 输入模式基类。tick 由 LevelActor 每帧驱动;on_tap 由 LevelActor 转发
# 相机的 tapped 信号(未拖动的单指触摸 / 鼠标左键点击世界)。
# 落在 UI 上的点击已被 GUI 消费,不会到达 on_tap,故无需在此做 UI 命中测试。

func enter():
	pass

func tick(in_delta: float):
	pass

func leave():
	pass

# 点击世界:screen_position 为视口坐标。默认无行为,子类按需覆写。
func on_tap(in_screen_position: Vector2):
	pass

# 视口坐标 → 落点格坐标;射线打不到 y=0 地面时返回 null。
func get_pointing_axis(in_screen_position: Vector2) -> Variant:
	var camera: CameraController = owner.get_camera()
	if not camera:
		return null
	var hit: Vector3 = camera.ground_point_from_screen(in_screen_position)
	if not hit.is_finite():
		return null
	return Vector2i(round(hit.x), round(hit.z))
