extends SceneTree

# conveyor regression: pickup / timed transport / delivery / blocking and retry / single-item
# carrying / not draining pure-demand bags, plus the Bag/Building transfer capability
# interface that supports it.
#   <godot.exe> --path <project> --headless --script res://test/conveyor_test.gd
#
# return = number of failed checks (0 = pass).
#
# delivery action: the "delivering" phase (and its HANDOFF_SECONDS) is only played when the
# downstream is a real BUILDING (stockpile, workshop, main base, ...). A belt-to-belt hand-off
# skips it and commits on the arrival frame -- adjacent belts' endpoints coincide on the shared
# cell edge, so the item stays continuous and no FRAMES_HANDOFF delay applies there.
#
# the fixture follows attack_preference_test's approach: Level is added to root => the
# building's _ready runs (bag creation); the map is flattened with MapData, then buildings
# are placed via Map.place_building. The conveyor's in-transit bag is deliberately not
# registered with Logistics, so this test does not need to wire up Logistics.

const DELTA: float = 0.05
# frames to cross one cell + 1: the pickup frame only loads the item and does not count
# toward travel. Derived from Conveyor.CELL_TRAVEL_SECONDS, so changing the belt speed in
# the backend is followed automatically and the test never drifts from the implementation.
const FRAMES_ONE_CELL: int = int(Conveyor.CELL_TRAVEL_SECONDS / DELTA) + 1
# frames needed for the delivery action + 1: the arrival frame only enters the delivery
# phase and does not count toward the action duration.
# Also derived from backend constants, so changing HANDOFF_SECONDS is followed automatically.
# ceili rather than int: 0.3 / 0.05 is 5.999999999999999 in double precision, and truncation
# would be one frame short (delivery not yet committed); frame-by-frame subtraction to 0
# actually takes 7 frames to commit, so round up then +1 to land exactly on the commit frame.
const FRAMES_HANDOFF: int = ceili(Conveyor.HANDOFF_SECONDS / DELTA) + 1
# frames needed for the pickup action + 1: the frame that starts the action only raises the
# phase, it does not count toward the action duration. Derived from the backend constant like
# the others, so changing PICK_SECONDS is followed automatically.
# ceili rather than int for the same reason as FRAMES_HANDOFF: 0.3 / 0.05 is 5.999999999999999
# in double precision and truncation would be one frame short.
const FRAMES_PICK: int = ceili(Conveyor.PICK_SECONDS / DELTA) + 1

var failed: int = 0
var level: Level = null

func _build_level() -> Level:
	var lvl := Level.new()
	root.add_child(lvl)
	Level.current = lvl
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
	lvl.map.load_data(map_data)
	return lvl

func _place(in_axis: Vector2i, in_type: String, in_direction: Vector2i) -> Building:
	var bd := BuildingData.new()
	bd.type = in_type
	bd.direction = in_direction
	var building: Building = level.map.place_building(in_axis, bd, true)
	# when running headless --script, SceneTree's root is not ready yet (Level cannot enter
	# the tree) and _ready does not fire automatically; call it once by hand so the building
	# creates its bag through the production path (same intent as workshop_progress_test's
	# manual bag creation).
	building._ready()
	return building

func _run(in_frames: int):
	for i in in_frames:
		level.tick(DELTA)

func _check(in_label: String, in_ok: bool):
	print("CASE ", in_label, " ok=", in_ok)
	if not in_ok:
		failed += 1

func _init():
	level = _build_level()

	# ===== 1. take -> cross one cell (1.0s) -> deliver =====
	# source = stockpile (storage type, can store and provide); middle = conveyor facing +X
	# (output end to the east); target = another stockpile.
	var src := _place(Vector2i(0, 0), "stockpile", Vector2i.RIGHT) as Stockpile
	src.store(5)
	var belt := _place(Vector2i(1, 0), "conveyor", Vector2i.RIGHT) as Conveyor
	var dst := _place(Vector2i(2, 0), "stockpile", Vector2i.RIGHT) as Stockpile
	var src_before: int = src.bag.count
	var dst_before: int = dst.bag.count

	_run(1)
	_check("1a empty belt takes one and starts the pickup phase (src -1 / on belt 1 / state=picking / pick_progress=0)",
			belt.bag.count == 1 and src.bag.count == src_before - 1 and belt.state == "picking"
			and is_zero_approx(belt.pick_progress))
	_check("1b progress=0 during the pickup (travel has not started)", is_zero_approx(belt.progress))

	_run(FRAMES_PICK)
	_check("1b2 pickup completes and only then does travel start (state=working / pick_progress=1 / progress=0)",
			belt.state == "working" and is_equal_approx(belt.pick_progress, 1.0)
			and is_zero_approx(belt.progress))

	_run(FRAMES_ONE_CELL - 1)
	_check("1c reaching the exit enters the delivery phase (item still on belt / downstream not increased / progress=1 / deliver_progress=0)",
			belt.state == "delivering" and belt.bag.count == 1 and dst.bag.count == dst_before
			and is_equal_approx(belt.progress, 1.0) and is_zero_approx(belt.deliver_progress))

	_run(FRAMES_HANDOFF)
	_check("1d only on delivery completion does it commit (target +1 / belt empty / state=idle)",
			dst.bag.count == dst_before + 1 and belt.bag.count == 0 and belt.state == "idle")

	# ===== 2. output end empty => blocked, and does not take a second item =====
	var src2 := _place(Vector2i(0, 1), "stockpile", Vector2i.RIGHT) as Stockpile
	src2.store(5)
	var belt2 := _place(Vector2i(1, 1), "conveyor", Vector2i.RIGHT) as Conveyor
	var src2_before: int = src2.bag.count
	_run(FRAMES_PICK + FRAMES_ONE_CELL + 40)
	_check("2a output end empty => state=blocked, item stays on belt", belt2.state == "blocked" and belt2.bag.count == 1)
	_check("2b progress stays at 1 while blocked", is_equal_approx(belt2.progress, 1.0))
	_check("2c while blocked it takes no second item (src -1 only)", src2.bag.count == src2_before - 1)

	# ===== 3. output end supplied => delivery resumes next frame =====
	var dst3 := _place(Vector2i(2, 1), "stockpile", Vector2i.RIGHT) as Stockpile
	var dst3_before: int = dst3.bag.count
	_run(1)
	_check("3a after the output end is supplied it first enters the delivery phase (item still on belt / downstream not increased)",
			belt2.state == "delivering" and belt2.bag.count == 1 and dst3.bag.count == dst3_before)

	_run(FRAMES_HANDOFF)
	_check("3b only on delivery completion does it commit (target +1 / belt empty / state=idle)",
			dst3.bag.count == dst3_before + 1 and belt2.bag.count == 0 and belt2.state == "idle")

	# ===== 4. target cannot accept (full) => blocked, no item lost =====
	var src4 := _place(Vector2i(0, 2), "stockpile", Vector2i.RIGHT) as Stockpile
	src4.store(5)
	var belt4 := _place(Vector2i(1, 2), "conveyor", Vector2i.RIGHT) as Conveyor
	var dst4 := _place(Vector2i(2, 2), "stockpile", Vector2i.RIGHT) as Stockpile
	dst4.store(Stockpile.CAPACITY)
	_check("4a target is full", dst4.is_full())
	_run(FRAMES_PICK + FRAMES_ONE_CELL + 10)
	_check("4b target full => state=blocked and no item lost", belt4.state == "blocked" and belt4.bag.count == 1)

	# ===== 5. Bag transfer capability predicates (the criteria conveyor take/deliver relies on) =====
	var storage := Bag.new()
	storage.item_type = "arrow"
	storage.max_count = 30
	storage.preferred_min_count = 0
	storage.preferred_max_count = 30
	storage.add_count_of("arrow", 5)
	_check("5a storage type: can provide, available=all stock, highest deposit rank (2)",
			storage.can_provide("arrow") and storage.available_to_provide("arrow") == 5 and storage.deposit_rank("arrow") == 2)
	_check("5b storage type: can accept", storage.can_accept("arrow"))

	var demand := Bag.new()
	demand.item_type = "log"
	demand.max_count = 30
	demand.preferred_min_count = 30
	demand.preferred_max_count = 30
	demand.add_count_of("log", 5)
	_check("5c pure demander: cannot provide (never drained)",
			not demand.can_provide("log") and demand.available_to_provide("log") == 0)
	_check("5d pure demander: can accept, highest deposit rank (2)", demand.can_accept("log") and demand.deposit_rank("log") == 2)

	var supply := Bag.new()
	supply.item_type = "arrow"
	supply.max_count = 30
	supply.preferred_min_count = 0
	supply.preferred_max_count = 0
	supply.add_count_of("arrow", 5)
	_check("5e pure supplier: can provide all, next-highest deposit rank (1)",
			supply.can_provide("arrow") and supply.available_to_provide("arrow") == 5 and supply.deposit_rank("arrow") == 1)

	# ===== 6. Building facade (conveyor take/deliver actually goes through it) =====
	# a separate stockpile: src has already been drained a lot by its own conveyor in earlier
	# rounds, so it cannot be reused for the "can provide" assertion.
	var lone := _place(Vector2i(1, 3), "conveyor", Vector2i.RIGHT) as Conveyor
	var storage_building := _place(Vector2i(3, 3), "stockpile", Vector2i.RIGHT) as Stockpile
	storage_building.store(5)
	_check("6a stockpile as a building: can provide and can accept",
			storage_building.can_provide("arrow") and storage_building.can_accept("arrow"))
	_check("6b conveyor exposes its in-transit bag, can accept while not full (must accept even when empty, otherwise chaining breaks)",
			lone.get_transfer_bags().size() == 1 and lone.can_accept("arrow"))
	_check("6c empty conveyor cannot provide", not lone.can_provide("arrow"))

	# ===== 7. conveyor chaining: the output end is another conveyor =====
	# a belt-to-belt hand-off plays no delivery action: the item is committed on the arrival
	# frame, so the upstream goes straight from "working" to "idle" and the downstream starts
	# travelling on that same frame (its timer is restarted by _on_hold_changed).
	var src7 := _place(Vector2i(0, 4), "stockpile", Vector2i.RIGHT) as Stockpile
	src7.store(3)
	var src7_before: int = src7.bag.count
	var belt7a := _place(Vector2i(1, 4), "conveyor", Vector2i.RIGHT) as Conveyor
	var belt7b := _place(Vector2i(2, 4), "conveyor", Vector2i.RIGHT) as Conveyor

	_run(FRAMES_PICK + FRAMES_ONE_CELL)
	_check("7a upstream hands over at the exit with no delivery action (downstream has 1 / upstream empty / neither delivering)",
			belt7b.bag.count == 1 and belt7a.bag.count == 0
			and belt7a.state == "idle" and belt7b.state == "working"
			and belt7a.deliver_progress == 0.0 and belt7b.deliver_progress == 0.0)
	_check("7b downstream really started travelling (not delivered in the same frame)", belt7b.progress < 1.0)

	_run(FRAMES_ONE_CELL)
	_check("7c downstream reaches its own exit with nothing at (3,4) => blocked, item not lost",
			belt7b.state == "blocked" and belt7b.bag.count == 1)
	_check("7d whole-chain conservation: src -2 (upstream re-picked one), each belt holds 1 (1+1+2=4)",
			src7.bag.count == src7_before - 2 and belt7a.bag.count == 1 and belt7b.bag.count == 1)

	# ===== 8. target cannot accept during delivery => abort midway back to blocked, item still on belt =====
	# after arriving and entering the delivery phase, fill the target during the delivery: the
	# next _tick_delivery re-check sees can_accept false and should abort midway
	# (deliver_progress zeroed, state=blocked); the item is always held by this belt and is
	# never lost.
	var src8 := _place(Vector2i(0, 5), "stockpile", Vector2i.RIGHT) as Stockpile
	src8.store(5)
	var belt8 := _place(Vector2i(1, 5), "conveyor", Vector2i.RIGHT) as Conveyor
	var dst8 := _place(Vector2i(2, 5), "stockpile", Vector2i.RIGHT) as Stockpile

	_run(FRAMES_PICK + FRAMES_ONE_CELL)
	_check("8a arrival enters the delivery phase (item still on belt / downstream not increased / deliver_progress=0)",
			belt8.state == "delivering" and belt8.bag.count == 1
			and dst8.bag.count == 1 and is_zero_approx(belt8.deliver_progress))

	dst8.store(Stockpile.CAPACITY)      # fill the downstream during delivery, the next frame's re-check sees it cannot accept
	_run(1)
	_check("8b target cannot accept during delivery => abort midway back to blocked (item still on belt / progress=1 / deliver_progress=0)",
			belt8.state == "blocked" and belt8.bag.count == 1
			and is_equal_approx(belt8.progress, 1.0) and is_zero_approx(belt8.deliver_progress))

	dst8.take(1)                        # free one slot to prove blocked is not a dead end and is recoverable
	_run(1)
	_check("8c after the target frees space it re-enters the delivery phase (item still on belt)",
			belt8.state == "delivering" and belt8.bag.count == 1)

	_run(FRAMES_HANDOFF)
	_check("8d only when the re-delivery completes does it commit (target back to full / belt empty / state=idle)",
			dst8.bag.count == Stockpile.CAPACITY and belt8.bag.count == 0 and belt8.state == "idle")

	# ===== 9. pickup action contract =====
	# the pickup is the mirror of the delivery action, with one deliberate asymmetry: unlike a
	# delivery (where the item stays on this belt until the action ends), the taken item is
	# deducted from the source on the very first frame. So a pickup always runs to completion,
	# and while it runs the belt must neither travel nor take a second item.
	var src9 := _place(Vector2i(0, 6), "stockpile", Vector2i.RIGHT) as Stockpile
	src9.store(5)
	var belt9 := _place(Vector2i(1, 6), "conveyor", Vector2i.RIGHT) as Conveyor
	var src9_before: int = src9.bag.count

	_run(1)
	_check("9a taking starts the pickup phase and already deducts the source (state=picking / pick_progress=0 / src -1 / on belt 1)",
			belt9.state == "picking" and is_zero_approx(belt9.pick_progress)
			and src9.bag.count == src9_before - 1 and belt9.bag.count == 1)
	_check("9b while picking the belt does not travel (progress=0) and takes no second item",
			is_zero_approx(belt9.progress) and src9.bag.count == src9_before - 1)
	_check("9c the pickup source is the input-end neighbour", belt9.get_pick_source() == src9)

	# mid-action: the progress is genuinely part-way through, and the belt still neither travels
	# nor takes a second item.
	_run(FRAMES_PICK - 2)
	_check("9d mid-pickup the progress is part-way and the belt does not travel (0<pick_progress<1 / progress=0 / no second item)",
			belt9.state == "picking" and belt9.pick_progress > 0.0 and belt9.pick_progress < 1.0
			and is_zero_approx(belt9.progress) and src9.bag.count == src9_before - 1)

	# one tick before completion: the phase is still running, but pick_progress already reads
	# exactly 1.0. That is not a bug -- the backend pins the progress at its endpoint and only
	# flips the state on the following tick, the same convention turret.gd documents for
	# load_progress ("load_progress reaches 1 first, then the state changes"), which is what lets
	# the presentation layer finish its animation exactly on the endpoint. So this asserts the
	# phase and the untravelled belt, NOT pick_progress < 1.
	_run(1)
	_check("9e one frame before completion the pickup phase is still running (state=picking / progress=0 / no second item; pick_progress is already pinned at 1)",
			belt9.state == "picking" and is_zero_approx(belt9.progress)
			and src9.bag.count == src9_before - 1)

	_run(1)
	_check("9f on completion the pickup ends at 1 and only then does travel start (state=working / pick_progress=1 / progress=0)",
			belt9.state == "working" and is_equal_approx(belt9.pick_progress, 1.0)
			and is_zero_approx(belt9.progress))

	_run(1)
	_check("9g travel has really started after the pickup (progress>0 / state=working)",
			belt9.progress > 0.0 and belt9.state == "working")

	Level.current = null      # leaving the static pointer unset would persist to exit and report a pile of ObjectDB leaks
	print("RESULT failed=", failed)
	quit(failed)
