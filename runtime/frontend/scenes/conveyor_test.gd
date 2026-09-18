extends Node3D

# 传送带循环测试场景:一个料堆 + 9 条传送带围成一圈,看货能不能绕圈转起来。
#
# 布局(俯视;世界 = (x, 0, y),故 y 越大越靠近屏幕下方):
#
#   y=0   ↓  ←  ←  ←      (0,0)↓  (1,0)←  (2,0)←  (3,0)←
#   y=1   ↓        ↑      (0,1)↓              (3,1)↑
#   y=2   仓 →  →  ↑      (0,2)仓  (1,2)→  (2,2)→  (3,2)↑
#
# 每格的 direction 就是它的输出方向,输入端 = axis - direction,于是整圈是:
#   料堆(0,2) → (1,2) → (2,2) → (3,2) → (3,1) → (3,0) → (2,0) → (1,0) → (0,0) → (0,1) → 回到料堆(0,2)
#
# (1,2) 没有上游传送带,它从输入端邻建 —— 也就是料堆 —— 取货;整圈最后一条 (0,1) 把货投回料堆。
# 料堆是"可存可取"的仓储型,既收得下也取得出,所以货会在圈里一直循环。
#
# 与 crossbow_test 同构:手工搭 backend(Level/Map)并每帧 tick;前端只用真实 BuildingActor
# 绑上去看模型/循环动画/承载物,不接 battle.tscn 的输入与 UI。

# { axis: direction(= 输出方向) }。缺的那格 (0,2) 是料堆。
const CONVEYOR_DIRECTIONS: Dictionary = {
	Vector2i(1, 2): Vector2i.RIGHT,   # 底部向右
	Vector2i(2, 2): Vector2i.RIGHT,
	Vector2i(3, 2): Vector2i.UP,      # 右侧向上(y 减小)
	Vector2i(3, 1): Vector2i.UP,
	Vector2i(3, 0): Vector2i.LEFT,    # 顶部向左
	Vector2i(2, 0): Vector2i.LEFT,
	Vector2i(1, 0): Vector2i.LEFT,
	Vector2i(0, 0): Vector2i.DOWN,    # 左侧向下
	Vector2i(0, 1): Vector2i.DOWN,
}
const STOCKPILE_AXIS: Vector2i = Vector2i(0, 2)
# 料堆里放多少件。要 >= 带条数 + 1:整圈九条带各持一件之后仓里还剩货,才能看出是"循环"
# 而不是"一次性把仓搬空"。
const STOCKPILE_SEED: int = 12
const STEP_DT: float = 1.0 / 60.0

var _level: Level = null
var _stockpile: Stockpile = null
var _conveyors: Array[Conveyor] = []
var _actors: Dictionary = {}   # { axis: BuildingActor },供接缝检查取模型
var _hud: Label = null

# 循环的客观判据:料堆存量每被取走/送回一次就变一次。变化次数持续上涨 ⇒ 货在圈里转,
# 而不是"一次性把仓搬空后卡死"。总量 min~max 顺带盯守恒(任何丢件/造件都会露馅)。
var _stock_min: int = 1 << 30
var _stock_max: int = -1
var _stock_flips: int = 0
var _last_stock: int = -1
var _total_min: int = 1 << 30
var _total_max: int = -1

func _ready():
	_build_backend()
	_build_frontend()

func _build_backend():
	_level = Level.new()
	add_child(_level)
	Level.current = _level

	var map_data := MapData.new()
	map_data.size = Vector2i(6, 6)
	map_data.cells = []
	for r in range(6):
		var row := CellRowData.new()
		row.cells = []
		for c in range(6):
			var cell := CellData.new()
			var land := LandData.new()
			land.type = "dirt"
			cell.land = land
			row.cells.append(cell)
		map_data.cells.append(row)
	_level.map.load_data(map_data)

	var stock_data := BuildingData.new()
	stock_data.type = "stockpile"
	stock_data.direction = Vector2i.UP
	_stockpile = _level.map.place_building(STOCKPILE_AXIS, stock_data, true) as Stockpile
	# 料堆放置时会自动填 1 件,这里补到 STOCKPILE_SEED。
	_stockpile.store(STOCKPILE_SEED)

	for axis: Vector2i in CONVEYOR_DIRECTIONS:
		var data := BuildingData.new()
		data.type = "conveyor"
		var direction: Vector2i = CONVEYOR_DIRECTIONS[axis]
		data.direction = direction
		var belt: Conveyor = _level.map.place_building(axis, data, true) as Conveyor
		_conveyors.append(belt)

func _build_frontend():
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.light_energy = 1.6
	add_child(sun)
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

	# 整圈占 x∈[0,3]、y∈[0,2],中心 (1.5, 0, 1.0)。
	var center := Vector3(1.5, 0.0, 1.0)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.current = true
	add_child(cam)
	cam.position = center + Vector3(2.6, 3.2, 3.0)
	cam.look_at(center, Vector3.UP)
	cam.fov = 45.0

	# 每栋建筑挂一个真实 BuildingActor:模型、循环动画、带上承载物全由它驱动。
	var actor_scene: PackedScene = preload("res://runtime/frontend/actors/building_actor.tscn")
	_spawn_actor(actor_scene, _stockpile)
	for belt: Conveyor in _conveyors:
		_spawn_actor(actor_scene, belt)

	_hud = Label.new()
	_hud.name = "HUD"
	_hud.position = Vector2(8, 8)
	_hud.add_theme_font_size_override("font_size", 16)
	add_child(_hud)

func _spawn_actor(in_scene: PackedScene, in_building: Building):
	var actor: Node3D = in_scene.instantiate()
	actor.name = "actor_%d_%d" % [in_building.axis.x, in_building.axis.y]
	add_child(actor)
	actor.bind(in_building)
	_actors[in_building.axis] = actor

# 接缝检查,分两类报:
#   直行对:A 的输出端 == B 的输入端。必须精确重合(0),否则物品跨带那一帧会跳。
#   拐角对:A 的输出落在 B 的侧面。直线传送带的输入端与输出端是相对的两条边,拐不了弯 ——
#          拐角只能靠上游往下游的侧面推货,而物品的显示起点仍在 B 的输入端(另一条边),
#          故这类天生错开一格。要真无缝得加一块"拐弯传送带"部件。
func seam_report() -> String:
	var worst: float = 0.0
	var corners: Array[String] = []
	for belt: Conveyor in _conveyors:
		var next_cell: Cell = _level.map.get_cell(belt.axis + belt.direction)
		var next_belt: Building = next_cell.building if next_cell else null
		if not (next_belt is Conveyor):
			continue
		if next_belt.axis - next_belt.direction != belt.axis:
			corners.append("%s->%s" % [belt.axis, next_belt.axis])
			continue
		var a_model: Node3D = _model_at(belt.axis)
		var b_model: Node3D = _model_at(next_belt.axis)
		if not a_model or not b_model:
			continue
		var a_out: Vector3 = a_model.global_transform * Vector3(ConveyorModel.BELT_OUTPUT_X, ConveyorModel.BELT_TOP_Y, 0.0)
		var b_in: Vector3 = b_model.global_transform * Vector3(ConveyorModel.BELT_INPUT_X, ConveyorModel.BELT_TOP_Y, 0.0)
		worst = maxf(worst, a_out.distance_to(b_in))
	return "直行接缝 %.5f 拐角 %s" % [worst, ",".join(corners)]

func _model_at(in_axis: Vector2i) -> Node3D:
	var actor: Node3D = _actors.get(in_axis)
	return actor.building_model if actor else null

func _process(_delta: float):
	_level.tick(STEP_DT)
	_update_hud()

# 报出"在仓 / 在带 / 在途 / 卡住"四项。判断转起来看两点:
#   * 总件数恒定(货既没卡死在某一格也没凭空消失);
#   * 在带件数稳定在接近带条数(每条带都咬着一件货在走),而不是一次性全堆到某处。
func _update_hud():
	var on_belts: int = 0
	var working: int = 0
	var blocked: int = 0
	for belt: Conveyor in _conveyors:
		on_belts += belt.bag.count
		if belt.state == "blocked":
			blocked += 1
		elif belt.state == "working":
			working += 1
	var stock: int = _stockpile.bag.count
	var total: int = stock + on_belts
	_stock_min = mini(_stock_min, stock)
	_stock_max = maxi(_stock_max, stock)
	_total_min = mini(_total_min, total)
	_total_max = maxi(_total_max, total)
	if _last_stock >= 0 and stock != _last_stock:
		_stock_flips += 1
	_last_stock = stock
	_hud.text = "料堆 %d (%d~%d, 翻转 %d) | 带上 %d/%d 在途 %d 卡住 %d | 总 %d (%d~%d) | %s" % [
		stock, _stock_min, _stock_max, _stock_flips,
		on_belts, _conveyors.size(), working, blocked,
		total, _total_min, _total_max, seam_report()]
