extends Node3D

# conveyor loop test scene: one stockpile + 9 conveyors arranged in a loop, to see whether
# goods can circulate around it.
#
# layout (top-down; world = (x, 0, y), so a larger y is closer to the bottom of the screen):
#
#   y=0   v  <- <- <-      (0,0)v  (1,0)<-  (2,0)<-  (3,0)<-
#   y=1   v        ^      (0,1)v              (3,1)^
#   y=2   S  -> -> ^      (0,2)S  (1,2)->  (2,2)->  (3,2)^
#
# each cell's direction is its output direction, input end = axis - direction, so the whole
# loop is:
#   stockpile(0,2) -> (1,2) -> (2,2) -> (3,2) -> (3,1) -> (3,0) -> (2,0) -> (1,0) -> (0,0) -> (0,1) -> back to stockpile(0,2)
#
# (1,2) has no upstream conveyor; it takes goods from its input-end neighbour -- the
# stockpile. The last belt of the loop, (0,1), delivers goods back to the stockpile.
# The stockpile is a "can store and can provide" storage type, able to both accept and
# provide, so goods keep circulating in the loop.
#
# Same shape as crossbow_test: build the backend (Level/Map) by hand and tick it every
# frame; the frontend only attaches real BuildingActors to watch the model/loop
# animation/payload, without wiring up battle.tscn's input and UI.

# { axis: direction (= output direction) }. The missing cell (0,2) is the stockpile.
const CONVEYOR_DIRECTIONS: Dictionary = {
	Vector2i(1, 2): Vector2i.RIGHT,   # bottom, pointing right
	Vector2i(2, 2): Vector2i.RIGHT,
	Vector2i(3, 2): Vector2i.UP,      # right side, pointing up (y decreases)
	Vector2i(3, 1): Vector2i.UP,
	Vector2i(3, 0): Vector2i.LEFT,    # top, pointing left
	Vector2i(2, 0): Vector2i.LEFT,
	Vector2i(1, 0): Vector2i.LEFT,
	Vector2i(0, 0): Vector2i.DOWN,    # left side, pointing down
	Vector2i(0, 1): Vector2i.DOWN,
}
const STOCKPILE_AXIS: Vector2i = Vector2i(0, 2)
# how many items the stockpile holds. Must be >= belt count + 1: only if goods remain in the
# bag after all nine belts in the loop each hold one can it be seen as "circulating" rather
# than "emptying the bag once".
const STOCKPILE_SEED: int = 12
const STEP_DT: float = 1.0 / 60.0

var _level: Level = null
var _stockpile: Stockpile = null
var _conveyors: Array[Conveyor] = []
var _actors: Dictionary = {}   # { axis: BuildingActor }, for the seam check to get models
var _hud: Label = null

# objective criterion for circulation: the stockpile count changes every time goods are taken
# or returned. A continuously rising flip count => goods are circulating rather than "emptied
# once then stuck". The total min~max also watches conservation (any lost/created item shows
# up).
var _stock_min: int = 1 << 30
var _stock_max: int = -1
var _stock_flips: int = 0
var _last_stock: int = -1
var _total_min: int = 1 << 30
var _total_max: int = -1
# objective criterion for the delivery action: the **peak lift** of the item off the belt
# surface (max over the session). Delivery is a short 0.3s action and catching it by
# screenshot is unreliable; "did the item ever leave the belt surface" only needs a nonzero
# value to prove the action really ran -- if the frontend were not drawing it, this value
# would stay 0. So take the session maximum rather than an instantaneous value.
var _lift_max: float = 0.0

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
	# placing the stockpile auto-fills 1 item; top it up to STOCKPILE_SEED here.
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

	# the loop occupies x in [0,3], y in [0,2], center (1.5, 0, 1.0).
	var center := Vector3(1.5, 0.0, 1.0)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.current = true
	add_child(cam)
	cam.position = center + Vector3(2.6, 3.2, 3.0)
	cam.look_at(center, Vector3.UP)
	cam.fov = 45.0

	# attach a real BuildingActor to each building: it drives the model, loop animation and
	# belt payload.
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

# seam check, reported in two categories:
#   straight pair: A's output end == B's input end. Must coincide exactly (0), otherwise the
#                  item jumps on the frame it crosses belts.
#   corner pair: A's output lands on B's side. A straight conveyor's input and output ends
#                are opposite edges and cannot turn a corner -- a corner can only push goods
#                from the upstream to the downstream's side, while the item's display start
#                is still at B's input end (the other edge), so this category is inherently
#                one cell out of alignment. True seamlessness would need a "corner conveyor"
#                piece.
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
	return "straight seam %.5f corners %s" % [worst, ",".join(corners)]

func _model_at(in_axis: Vector2i) -> Node3D:
	var actor: Node3D = _actors.get(in_axis)
	return actor.building_model if actor else null

func _process(_delta: float):
	_level.tick(STEP_DT)
	_update_hud()

# report the counts "in stock / on belts / working / delivering / blocked", plus the session
# peak lift. Two things tell whether the loop is running:
#   * the total item count is constant (goods neither stuck dead in one cell nor vanished);
#   * the on-belt count stabilizes near the belt count (every belt is carrying one item),
#     rather than all piling up somewhere at once.
# The peak lift is the objective proof that the delivery action really plays; see _lift_max.
func _update_hud():
	var on_belts: int = 0
	var working: int = 0
	var blocked: int = 0
	var delivering: int = 0
	for belt: Conveyor in _conveyors:
		on_belts += belt.bag.count
		if belt.state == "blocked":
			blocked += 1
		elif belt.state == "working":
			working += 1
		elif belt.state == "delivering":
			delivering += 1
		_lift_max = maxf(_lift_max, _item_lift(belt))
	var stock: int = _stockpile.bag.count
	var total: int = stock + on_belts
	_stock_min = mini(_stock_min, stock)
	_stock_max = maxi(_stock_max, stock)
	_total_min = mini(_total_min, total)
	_total_max = maxi(_total_max, total)
	if _last_stock >= 0 and stock != _last_stock:
		_stock_flips += 1
	_last_stock = stock
	_hud.text = "stock %d (%d~%d, flips %d) | belts %d/%d working %d delivering %d blocked %d | total %d (%d~%d) | peak lift %.3f | %s" % [
		stock, _stock_min, _stock_max, _stock_flips,
		on_belts, _conveyors.size(), working, delivering, blocked,
		total, _total_min, _total_max, _lift_max, seam_report()]

# how far the item this belt carries has lifted off the belt surface (world Y, metres).
# 0 while it slides along the belt; > 0 only while the delivery action carries it through the
# inverted-U arc. An empty belt, or a belt whose model is not placed, reports 0.
func _item_lift(in_belt: Conveyor) -> float:
	if in_belt.bag.count <= 0:
		return 0.0
	var model: Node3D = _model_at(in_belt.axis)
	if not model:
		return 0.0
	var stack: Node3D = model.get_node_or_null("hold_stack")
	if not stack:
		return 0.0
	var surface_y: float = (model.global_transform * Vector3(0.0, ConveyorModel.BELT_TOP_Y, 0.0)).y
	return stack.global_position.y - surface_y
