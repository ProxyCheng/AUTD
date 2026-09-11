extends Node3D

# Crossbow 动画集成测试:构造真实 backend(Level/Map/Crossbow/敌人),只 tick backend,
# 让 Crossbow 状态机自己产生 state/progress,前端经 BuildingActor 信号绑定自动跟随。
# 模拟一名操作工每帧经 crossbow.work(delta) 注入工作量(等价 ProvideWorkloadTask 的公开 API),
# 于是弩走完 idle→loading→charging→ready→firing→idle 循环,可观察三段动画。
# 不 tick 则 progress 冻结;tick 一下 progress 才动——完全符合 AGENTS.md 状态流约定。

var _level: Level = null
var _crossbow: Crossbow = null
var _walking: bool = true     # 是否有一位操作工在位注入工作量
var _worker_absent_frames: int = 0   # 每轮射击后让工人缺位多少帧,模拟离岗→重新到岗(触发 reload)
var _step_dt: float = 1.0 / 60.0
var _hud: Label = null
var _enemy: Enemy = null
var _actor: Node3D = null
var _flight_actor: EntityActor = null   # 飞行箭的 EntityActor 镜像(观察俯仰)
var _freeze_on_flight: bool = false   # 观察飞行箭:出现即冻结,便于稳定截图

func _ready():
	_build_backend()
	_build_frontend()
	# 打开"冻结在飞行瞬间",便于一次截图捕捉抛物线
	_freeze_on_flight = true
	# 监听 entity 增删,为飞行箭创建 EntityActor(绕过 camera 可见性逻辑,纯观察用)
	_level.room.entities_changed.connect(_on_entities_changed)

func _on_entities_changed(in_added: Array, _in_removed: Array):
	for eid in in_added:
		var e = _level.room.get_entity(eid)
		if e is Arrow:
			if _flight_actor:
				_flight_actor.queue_free()
			var ea_tscn: PackedScene = preload("res://runtime/frontend/actors/entity_actor.tscn")
			_flight_actor = ea_tscn.instantiate()
			_flight_actor.name = "flight_actor"
			add_child(_flight_actor)
			_flight_actor.bind(e)

# —— backend:搭一个可 tick 的 Level,放弩与敌人 —— #
func _build_backend():
	_level = Level.new()
	add_child(_level)
	Level.current = _level

	# 小地图 8×8 全 dirt
	var map_data := MapData.new()
	map_data.size = Vector2i(8, 8)
	map_data.cells = []
	for r in range(8):
		var row := CellRowData.new()
		row.cells = []
		for c in range(8):
			var cell := CellData.new()
			var land := LandData.new()
			land.type = "dirt"
			cell.land = land
			row.cells.append(cell)
		map_data.cells.append(row)
	_level.map.load_data(map_data)

	# 在 (3,3) 放弩
	var bd := BuildingData.new()
	bd.type = "crossbow"
	bd.direction = Vector2i.UP
	var xb: Building = _level.map.place_building(Vector2i(3, 3), bd, true)
	_crossbow = xb as Crossbow

	# 填弹药(弩在 _ready 已建 AmmoBag)
	_crossbow.input_bag.add_count(8)

	# 放一个敌人(射程内 axis±3),静止不动(关掉寻路),供 find_target
	var enemy: Enemy = Entity.create("enemy") as Enemy
	enemy.position = Vector2(3, 5)   # 距弩 (0,2),在 6×6 范围内
	enemy.move_speed = 0.0           # 原地,便于观察
	_level.room.add_entity(enemy)
	_enemy = enemy

func _build_frontend():
	# 灯
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	light.light_energy = 1.6
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(140), 0)
	fill.light_energy = 0.7
	add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 相机:普通 Camera3D(不用 CameraController,避免其接管相机运动)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.current = true
	add_child(cam)
	cam.position = Vector3(3.0 + 1.1, 1.5, 3.0 + 2.3)
	cam.look_at(Vector3(3.0, 0.9, 3.0), Vector3.UP)
	cam.fov = 40.0

	# 建筑 actor:绑定 Crossbow,前端信号驱动模型(bind 会把 actor 定位到 building.axis (3,3))
	var actor_tscn: PackedScene = preload("res://runtime/frontend/actors/building_actor.tscn")
	var actor: Node3D = actor_tscn.instantiate()
	actor.name = "building_actor"
	add_child(actor)
	actor.bind(_crossbow)
	# bind 已按 axis 设 position=(3,0,3),相机已对准该处
	_actor = actor

	# HUD 显示 backend 状态/进度
	_hud = Label.new()
	_hud.name = "HUD"
	_hud.position = Vector2(8, 8)
	_hud.add_theme_font_size_override("font_size", 18)
	add_child(_hud)

func _tick_backend_per_frame():
	if _walking:
		# 模拟操作工在岗:每帧注入工作量(delta * 1.0 效率)
		_crossbow.work(_step_dt)
	else:
		# 工人缺位:让 _manned_timer 随时间衰减,直至 _is_manned() 转 false
		_worker_absent_frames -= 1
		if _worker_absent_frames <= 0:
			_walking = true   # 新工人到岗(下一帧 work() 触发 was_unmanned → _reset_shift → reload)
	_level.tick(_step_dt)

func _process(delta: float):
	# 若开启"冻结在飞行"且已有飞行箭,则停住,便于稳定截图观察抛物线
	var has_flight := false
	for e in _level.room.entities.values():
		if e is Arrow:
			has_flight = true
			break
	if _freeze_on_flight and has_flight:
		_update_hud()
		return   # 不 tick backend,飞行箭定格
	_tick_backend_per_frame()
	# 感知"本轮生产完成"(worker 应离岗):_shift_fired 且回到 idle/firing 结束 → 停岗一段时间
	if _walking and _crossbow._shift_fired and _crossbow.state == "idle":
		_walking = false
		_worker_absent_frames = 20   # ~0.33s 缺位,足够 _manned_timer 超时 → 触发新工人到岗
	_update_hud()
func _update_hud():
	var arrow: Node3D = null
	var model: Node3D = null
	if _actor:
		model = _actor.get("building_model") as Node3D
		if model:
			arrow = model.get_node_or_null("%Arrow")
	var arrow_vis: bool = arrow.visible if arrow else false
	var ammo: int = _crossbow.input_bag.count if _crossbow.input_bag else -1
	# 飞行箭(抛物线验证):扫描 room 里的 arrow 实体,读其 flight_progress/位置/俯仰
	var flight_info := "flight=none"
	for e in _level.room.entities.values():
		if e is Arrow:
			var pitch := 0.0
			if _flight_actor and _flight_actor.model:
				pitch = rad_to_deg(_flight_actor.model.global_rotation.x)
			flight_info = "flight prog=%.2f pos=(%.2f,%.2f) h=%.2f pitch=%.1fdeg" % [
				e.flight_progress(), e.position.x, e.position.y, e.launch_height, pitch]
			break
	_hud.text = "state=%s progress=%.2f ammo=%d | %s | %s" % [
		_crossbow.state, _crossbow.progress, ammo,
		str(arrow_vis), flight_info]
