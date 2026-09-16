class_name InspectMode
extends Mode

# 检视模式:面板打开期间接管输入 —— 桌面 ESC 或面板 × 关闭回 roaming;
# 点另一目标(建筑或工人)则切换选中并刷新面板(无需先关面板);点空白处关闭。
# 面板 UI 上的触摸/点击由 GUI 消费,不会到达 on_tap,故无需额外做 UI 命中测试。
# 面板关闭来自三条路径:① ESC → owner.close_inspector();② 面板内 × 按钮 →
# BuildingInspectorHost._on_panel_closed → owner.close_inspector();③ 点空白/另一目标。
# 全部汇聚到 LevelActor.inspect_target/close_inspector,故本类不负责 leave 清理。

func tick(_in_delta: float):
	if Input.is_key_pressed(KEY_ESCAPE):
		owner.close_inspector()

func on_tap(in_screen_position: Vector2):
	# 实体优先:与 roaming 同序(见 RoamingMode.on_tap);点到别的工人即换绑检视。
	var entity: Entity = owner.pick_entity(in_screen_position)
	if entity:
		if entity != owner.selected_target:
			owner.inspect_target(entity)
		return
	var axis: Variant = get_pointing_axis(in_screen_position)
	if axis == null:
		return
	var map: Map = Level.current.map
	var cell: Cell = map.get_cell(axis)
	# 点空白处(无建筑格):关闭检视面板并清选中,回 roaming。
	if not cell or not cell.building:
		owner.close_inspector()
		return
	# 点到了另一建筑:重新选中并刷新面板(切换);点到当前选中建筑则保持
	if cell.building != owner.selected_target:
		owner.inspect_target(cell.building)
