class_name LevelActor
extends Node

@export
var level_data: LevelData

@export
var speed: float = 1

var level: Level = null
var mode: Mode = null

# —— 当前选中的检视目标(frontend 持有;表现层概念,backend 不作记录)——
# selected_target 变化 → selected_changed;drives 高亮 + 检视面板。
# 目标可为 Building,也可为 Entity(工人等),故用 Object 承载。
var selected_target: Object = null
signal selected_changed(target: Object)

# actor 按可见性回收/重建,故选中高亮通过 actor 处理(见 map_actor 与 room_actor),
# 这里记录的是 backend 对象(生命周期在 Map / Room)。

func bind(in_level: Level):
	level = in_level
	level.owner = owner
	add_child(level)
	%map.bind(level.map)
	%room.bind(level.room)
	# 选中实体被移除(死亡/命中)时关闭检视面板:queue_free 延迟执行,回调期间实体仍有效,
	# 读 .id 安全(Room.entities_changed 移除事件)。
	level.room.entities_changed.connect(_on_room_entities_changed)

# 房间实体增删:仅关心当前选中实体被移除的情况(其余表现交给 room_actor)。
func _on_room_entities_changed(in_added_entity_ids: Array, in_removed_entity_ids: Array):
	var target_entity: Entity = selected_target as Entity
	if not target_entity:
		return
	if in_removed_entity_ids.has(target_entity.id):
		close_inspector()

func get_camera() -> CameraController:
	return %camera

# 跨 actor 的世界空间表现(如物品搬运飞行)按 backend 建筑取当前 actor;
# 建筑不可见/未放置 → null。收敛在此,免得各 actor 自己去摸 %map。
func get_building_actor(in_building: Building) -> BuildingActor:
	return %map.get_building_actor(in_building)

# 相机的"点击世界"事件转发给当前模式(触屏与鼠标统一入口)。
func _on_camera_tapped(in_screen_position: Vector2):
	if mode:
		mode.on_tap(in_screen_position)

# 世界点击拾取:对全部可见建筑 actor 与实体 actor 做同一套射线-AABB,取最近命中。
# 建筑与实体同池判定 → 工人站在建筑后面时近者胜出(遮挡正确),无命中返回 null。
func pick_target(in_screen_position: Vector2) -> Object:
	var camera: CameraController = get_camera()
	if not camera:
		return null
	var origin: Vector3 = camera.project_ray_origin(in_screen_position)
	var direction: Vector3 = camera.project_ray_normal(in_screen_position)
	var candidates: Array[Node3D] = %map.pick_candidates()
	candidates.append_array(%room.pick_candidates())
	var best_distance: float = INF
	var picked: Object = null
	for actor: Node3D in candidates:
		var distance: float = actor.ray_hit_distance(origin, direction)
		if distance >= 0.0 and distance < best_distance:
			best_distance = distance
			picked = actor.pick_target()
	return picked

# —— 检视目标(GUI 侧栏)——
# 打开选中目标的检视面板:记录选中 → 高亮 → 分发到面板 → 切到 inspect mode。
# 目标可为 Building 或 Entity;面板是屏幕空间 Control(挂 %inspector CanvasLayer),非世界空间头顶条。
func inspect_target(in_target: Object) -> bool:
	select_target(in_target)
	var panel: Node = %inspector.get_node("Panel")
	if not panel or not panel.has_method(&"configure"):
		return false
	# configure 返回 true 才说明有对应面板被打开;
	# 无面板目标(main_base/enemy_spawner 等)撤销选中(去掉高亮),保持当前模式。
	if panel.call(&"configure", in_target):
		AudioManager.sfx(&"ui_open")
		set_mode(&"inspect")
		return true
	# 该目标没有对应面板:选中随即被撤销。
	# 给一声"点到了但不可检视"的反馈,避免点击完全没响应。
	AudioManager.sfx(&"ui_select")
	clear_selection()
	return false

# 记录当前选中目标并广播(高亮 actor 由 map_actor / room_actor 监听 selected_changed 驱动)。
func select_target(in_target: Object):
	if in_target == selected_target:
		return
	selected_target = in_target
	selected_changed.emit(in_target)

# 清空选中(关闭检视或取消选中时);不发强制的无面板关闭。
func clear_selection():
	if selected_target == null:
		return
	selected_target = null
	selected_changed.emit(null)

# —— 检视面板开关 ——
# _dismissing 防重入:panel.close() 会同步回调 BuildingInspectorHost → close_inspector(),
# 若不拦截会形成 close_inspector → _dismiss_inspector → panel.close 的级联递归
# (重复关面板 / 二次 set_mode / ui_toggle 响两声)。
var _dismissing: bool = false

# 关闭面板但**不**切模式(close_inspector 与 set_mode 共用);级联重入在此被拦下。
func _dismiss_inspector():
	if _dismissing:
		return
	_dismissing = true
	clear_selection()
	%inspector.get_node("Panel").call(&"close")
	_dismissing = false

# 关闭检视面板并回到 roaming;先清空选中(面板已在关闭时清除绑定)。
func close_inspector():
	if _dismissing:
		return
	_dismiss_inspector()
	set_mode(&"roaming")

# 删除建筑(检视面板内 Delete 按钮触发):先关闭面板(断开其对 building 的绑定),
# 再经 backend map.remove_building(axis) 销毁建筑并广播 cells_changed,由 frontend 回收 actor。
func delete_building(in_building: Building):
	if in_building == null:
		return
	close_inspector()
	if level and level.map:
		var axis: Vector2i = in_building.axis
		level.map.remove_building(axis)
		AudioManager.sfx_at(&"build_remove", Vector3(axis.x, 0, axis.y))

func set_mode(in_mode_id: StringName):
	# 切到非检视模式时,先关掉还开着的检视面板,避免面板跨模式残留。
	# _dismiss_inspector 自带 _dismissing 守卫:close_inspector 自己的 set_mode 不会二次关闭。
	if in_mode_id != &"inspect" and mode is InspectMode:
		_dismiss_inspector()
	var had_mode: bool = mode != null
	if mode:
		mode.leave()
		mode = null
	for m in %modes.get_children():
		if m.name == in_mode_id:
			mode = m as Mode
			break
	if mode:
		mode.enter()
	# 仅"已有模式 → 切换"时发声:启动首个 set_mode 静默,inspect 另用开面板音。
	if had_mode and in_mode_id != &"inspect":
		AudioManager.sfx(&"ui_toggle")

func _ready():
	assert(level_data)
	# 子节点 %audio 的 _ready 先于本节点执行,故此处赋值时播放器已就绪(§5.1)。
	AudioManager.current = %audio
	bind(Level.new())
	Level.current = level
	level.load_data(level_data)
	_start_audio()
	get_camera().tapped.connect(_on_camera_tapped)

	set_mode(&"roaming")

# 启动背景音乐与环境音;素材与授权见 runtime/frontend/audio/LICENSES/。
# 资源未登记时 AudioManager 静默跳过,故可先行调用。
func _start_audio():
	AudioManager.music(&"bgm")
	AudioManager.ambience(&"ambience")

func _process(in_delta: float):
	level.tick(in_delta * speed)
	if mode:
		mode.tick(in_delta)
	else:
		set_mode(&"roaming")
