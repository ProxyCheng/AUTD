class_name LevelActor
extends Node

@export
var level_data: LevelData

@export
var speed: float = 1

var level: Level = null
var mode: Mode = null

# —— 当前选中的建筑(frontend 持有;表现层概念,backend 不作记录)——
# selected_building 变化 → selected_changed;drives 高亮 + 检视面板。
var selected_building: Building = null
signal selected_changed(building: Building)

# 建筑 actor 按可见性回收/重建,故选中高亮通过 actor 处理(见 map_actor 与
# BuildingActor.set_selected),这里记录的是 backend Building 对象(生命周期在 Map)。

func bind(in_level: Level):
	level = in_level
	level.owner = owner
	add_child(level)
	%map.bind(level.map)
	%room.bind(level.room)

func get_camera():
	return %camera

# —— 建筑检视(GUI 侧栏)——
# 打开选中建筑的检视面板:记录选中 → 高亮 → 分发到对应面板 → 切到 inspect mode。
# 面板是屏幕空间 Control(挂 %inspector CanvasLayer),非世界空间头顶条。
func inspect_building(in_building: Building):
	select_building(in_building)
	var panel: Node = %inspector.get_node("Panel")
	if not panel or not panel.has_method(&"configure"):
		return
	# configure 返回 true 才说明有对应面板被打开;
	# 无面板建筑(main_base/enemy_spawner 等)撤销选中(去掉高亮),保持 roaming。
	if panel.call(&"configure", in_building):
		AudioManager.sfx(&"ui_open")
		set_mode(&"inspect")
	else:
		clear_selection()

# 记录当前选中建筑并广播(高亮 actor 由 map_actor 监听 selected_changed 驱动)。
func select_building(in_building: Building):
	if in_building == selected_building:
		return
	selected_building = in_building
	selected_changed.emit(in_building)

# 清空选中(关闭检视或取消选中时);不发强制的无面板关闭。
func clear_selection():
	if selected_building == null:
		return
	selected_building = null
	selected_changed.emit(null)

# 关闭检视面板并回到 roaming;先清空选中(面板已在关闭时清除绑定)。
func close_inspector():
	clear_selection()
	%inspector.get_node("Panel").call(&"close")
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
