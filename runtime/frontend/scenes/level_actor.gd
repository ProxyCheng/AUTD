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
	# configure 返回 true 才说明有对应面板被打开;main_base/enemy_spawner 等无面板时保持 roaming
	if panel.call(&"configure", in_building):
		set_mode(&"inspect")

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

func set_mode(in_mode_id: StringName):
	if mode:
		mode.leave()
		mode = null
	for m in %modes.get_children():
		if m.name == in_mode_id:
			mode = m as Mode
			break
	if mode:
		mode.enter()

func _ready():
	assert(level_data)
	bind(Level.new())
	Level.current = level
	level.load_data(level_data)
	
	set_mode(&"roaming")

func _process(in_delta: float):
	level.tick(in_delta * speed)
	if mode:
		mode.tick(in_delta)
	else:
		set_mode(&"roaming")
