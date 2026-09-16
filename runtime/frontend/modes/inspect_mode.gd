class_name InspectMode
extends Mode

# 检视模式:面板打开期间接管输入 —— 桌面 ESC 或面板 × 关闭回 roaming;
# 点另一目标(建筑或工人)则切换选中并刷新面板(无需先关面板);点空白处关闭。
# 目标解析与 roaming 同入口:LevelActor.pick_target 对建筑/工人统一做射线-AABB,最近命中者胜。
# 面板 UI 上的触摸/点击由 GUI 消费,不会到达 on_tap,故无需额外做 UI 命中测试。
# 面板关闭来自三条路径:① ESC → owner.close_inspector();② 面板内 × 按钮 →
# BuildingInspectorHost._on_panel_closed → owner.close_inspector();③ 点空白/另一目标。
# 全部汇聚到 LevelActor.inspect_target/close_inspector,故本类不负责 leave 清理。

func tick(_in_delta: float):
	if Input.is_key_pressed(KEY_ESCAPE):
		owner.close_inspector()

func on_tap(in_screen_position: Vector2):
	# 与 roaming 同一拾取入口:建筑/工人同池射线-AABB,最近命中者胜。
	var target: Object = owner.pick_target(in_screen_position)
	if not target:
		# 点空白处(无命中):关闭检视面板并清选中,回 roaming。
		owner.close_inspector()
		return
	# 点到了另一目标:重新选中并刷新面板(切换);点到当前选中目标则保持
	if target != owner.selected_target:
		owner.inspect_target(target)
