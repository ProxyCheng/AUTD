class_name Conveyor
extends Building

# Conveyor: single cell, single item in-transit buffer. Each tick takes one item from the
# "input end" (axis - direction) neighbour, carries it on the belt surface for
# CELL_TRAVEL_SECONDS seconds, then delivers it to the "output end" (axis + direction)
# neighbour; if it cannot deliver it blocks (state = "blocked") and retries every frame --
# while one item has not been sent on it never takes the next one, so the whole line is
# blocking (like a Factorio belt, it backs up when full).
#
# direction comes from BuildingData.direction (grid vector, the model front -Z faces it) =
# output direction; so input end = axis - direction, output end = axis + direction. The
# player steps it 90 degrees at placement time with rotate_building_left /
# rotate_building_right (see BuildingMode).
#
# both take and deliver go through Building's transfer capability interface (provide_to /
# accept_from), sharing the same Bag criteria as worker hauling: storage types like the
# stockpile (can store and can provide) can be taken from, workshop input bags (pure
# demanders) are never drained.
# the output end may be another conveyor -- its in-transit buffer is exposed via
# get_transfer_bags and it can accept as long as it is not full.
#
# presentation contract (section 5.4):
#   state    "idle" (empty, waiting to take) / "working" (in transit) / "blocked" (cannot deliver, stuck)
#   state    "delivering" = the item has reached the belt exit and is being "handed" to the
#            downstream (delivery action). Only for a real building downstream -- a belt-to-belt
#            hand-off is instant and continuous (see _try_deliver), so this phase never appears
#            between two conveyors.
#   progress [0,1] travel progress, 0 = just picked up, 1 = should deliver; after arriving it
#            stays at 1 until delivered
#   deliver_progress [0,1] delivery action progress, 0 = just started handing, 1 = handed and
#            should commit; only meaningful during "delivering", i.e. only when the downstream
#            is not a conveyor
#   the payload hangs on its own bag, frontend mirrors it via get_display_bag() (section 5.5)

# time (seconds) for one item to cross one cell. Reciprocal of ConveyorModel.DEFAULT_SPEED
# (one cell = 1 unit): the belt cleats move at the same speed as the item, so changing this
# means changing that constant too.
const CELL_TRAVEL_SECONDS: float = 2.0

# in-transit buffer capacity: only one item at a time.
const CAPACITY: int = 1

# delivery action duration (seconds): after the item reaches the belt exit, this is the time
# spent "handing" it to the downstream neighbour. Same order of magnitude as a worker
# dropping goods (ItemTransfer.PER_ITEM_DURATION), so "delivery" reads as an action and not
# a teleport.
const HANDOFF_SECONDS: float = 0.3

# in-transit buffer. Deliberately **not registered with Logistics** -- it is only the
# conveyor's internal buffer, not a logistics supply/demand node; if registered it would be
# treated as a pickup source / deposit point and fight the conveyor's own take/deliver logic.
var bag: Bag = null

# remaining travel time (seconds); > 0 means an item is on the belt and moving.
var _travel_left: float = 0.0

# remaining delivery time (seconds); > 0 means we are in the "delivering" phase.
var _handoff_left: float = 0.0

# delivery action progress [0,1] (section 5.4 contract: the data layer only emits normalized
# values). It is this building's **second** progress -- belt travel is still expressed by
# progress, kept separate, for the same reason as Turret.load_progress (different phases of
# the same building each get their own).
var deliver_progress: float = 0.0:
	get:
		return deliver_progress
	set(in_progress):
		if is_equal_approx(in_progress, deliver_progress):
			return
		deliver_progress = in_progress
		deliver_progress_changed.emit()
signal deliver_progress_changed()

func _ready():
	bag = Bag.new()
	bag.name = "Bag"
	bag.max_count = CAPACITY
	# wildcard: the conveyor does not restrict cargo type, and item_type is empty when idle --
	# without the wildcard, can_accept(any type) would be false due to the type mismatch and
	# the downstream could never accept goods (chaining would break outright).
	bag.accepts_any_type = true
	# accept only, never provide: the in-transit bag only accepts goods **pushed in** by the
	# upstream, and is never drained as a source by another conveyor. Otherwise the downstream
	# would "suck" the item away on the very frame the upstream picks it up -- the item would
	# effectively teleport, the upstream belt travel would be wasted, and the flow would be
	# wrong. This belt's own delivery goes through Bag.move_to (not can_provide), so it is
	# unaffected.
	bag.preferred_min_count = CAPACITY
	bag.preferred_max_count = CAPACITY
	# cell is injected by Map.place_building before add_child, so it is available in _ready;
	# when manually new'd in tests and not attached to a cell, fall back to the origin.
	bag.access_position = Vector2(axis) if cell else Vector2.ZERO
	add_child(bag)
	bag.owner = owner
	bag.count_changed.connect(_on_hold_changed)

# the payload is given to the frontend mirror (ItemStack), see section 5.5.
func get_display_bag() -> Bag:
	return bag

# the in-transit buffer takes part in hauling: other conveyors (or the building capability
# interface) use this to push goods in -- it can accept as long as it is not full.
# note this only affects Building's capability interface, Logistics cannot see it (this bag
# is not registered).
func get_transfer_bags() -> Array[Bag]:
	var bags: Array[Bag] = [bag]
	return bags

func tick(in_delta: float):
	if not bag:
		return
	if bag.count <= 0:
		_try_extract()
		return
	if state == "delivering":
		_tick_delivery(in_delta)
		return
	_travel_left = maxf(_travel_left - in_delta, 0.0)
	progress = clampf(1.0 - _travel_left / CELL_TRAVEL_SECONDS, 0.0, 1.0)
	if _travel_left > 0.0:
		state = "working"
		return
	_try_deliver()

# empty: take one item from the input-end neighbour (any type; the other side picks the type
# it has and can provide). Starting the timer and the display type are both settled in
# _on_hold_changed (the taken item triggers count_changed).
func _try_extract():
	var source: Building = _neighbour(-direction)
	if source == null or source.provide_to(bag, "", 1) <= 0:
		state = "idle"
		progress = 0.0

# in-transit buffer count changed: whether the item was taken by this belt itself
# (_try_extract) or pushed in by an upstream conveyor, it is all settled here -- both start
# the timer and fix the display type.
#   * start the timer: without it, the pushed-in item would be delivered directly on the same
#     frame because _travel_left is still 0, skipping the whole transport.
#   * display type: the frontend ItemStack uses bag.item_type to decide what to draw. If it
#     were only written on the pickup path, a belt that got its item "pushed in" would always
#     have an empty item_type and could not draw the item (observed: in a full loop only the
#     belt fed by the stockpile could show an item).
func _on_hold_changed():
	if bag.count <= 0:
		return
	if bag.item_type.is_empty():
		var types: Array[String] = bag.types()
		if not types.is_empty():
			bag.item_type = types[0]
	if _travel_left <= 0.0:
		_travel_left = CELL_TRAVEL_SECONDS
		progress = 0.0
		state = "working"

# arrived: hand the item over. If the downstream is another conveyor, commit immediately and
# skip the delivery action -- adjacent belts' endpoints coincide on the cell edge, so the item
# appears on the next belt exactly where it left this one and the flow stays continuous;
# playing the action there would lift the item off the belt and stall the line for
# HANDOFF_SECONDS for no visual gain. The action is for handing goods to a real building.
func _try_deliver():
	var held_type: String = _held_type()
	var target: Building = _neighbour(direction)
	if held_type.is_empty() or target == null or not target.can_accept(held_type):
		state = "blocked"
		return
	if target is Conveyor:
		# a failed commit here (can_accept said yes but the move did not happen) must read as
		# blocked, exactly like the building path, so a backed-up line still shows as backed up.
		if not _commit_to(target, held_type):
			state = "blocked"
		return
	_begin_delivery()

# begin delivery: the item **is still in its own bag** (not deducted first) -- this bag is
# the custodian for the whole process. Precisely because of that, the downstream does not yet
# have this item, so the flying item drawn by the presentation layer and the item in the
# downstream stack can never exist at the same time.
func _begin_delivery():
	_handoff_left = HANDOFF_SECONDS
	deliver_progress = 0.0
	state = "delivering"

# advance delivery. Every tick re-checks whether the downstream can still accept: during
# those 0.3 seconds it may have been filled by another conveyor/worker, in which case it
# falls back to blocked (the item is always on this belt, falling back costs nothing, and an
# item is never lost).
func _tick_delivery(in_delta: float):
	if not _can_deliver():
		_abort_delivery()
		return
	_handoff_left = maxf(_handoff_left - in_delta, 0.0)
	deliver_progress = 1.0 - _handoff_left / HANDOFF_SECONDS
	if _handoff_left <= 0.0:
		_commit_delivery()

# commit the carried item to the downstream. accept_from is the single implementation of the
# bag-selection rule; this class does not reimplement bag selection. Returns false when the
# downstream cannot take it (caller decides what that means).
func _commit_to(in_target: Building, in_held_type: String) -> bool:
	if in_target == null or in_held_type.is_empty() or in_target.accept_from(bag, in_held_type, 1) <= 0:
		return false
	bag.item_type = ""
	_travel_left = 0.0
	progress = 0.0
	deliver_progress = 0.0
	state = "idle"
	return true

func _commit_delivery():
	if _commit_to(_neighbour(direction), _held_type()):
		return
	_abort_delivery()

# abort midway / commit failed: return to the blocked state. The item is always on this belt,
# so it is enough to zero the delivery progress and hand the state back to blocked; progress
# stays at 1 (the item is at the exit) and the retry continues next frame.
func _abort_delivery():
	deliver_progress = 0.0
	state = "blocked"

# whether the downstream can still accept this item right now. Must be a non-destructive
# predicate -- accept_from actually moves goods, so during delivery we can only ask, not call
# it, otherwise the goods would already have moved before the delivery action finished
# playing.
func _can_deliver() -> bool:
	var target: Building = _neighbour(direction)
	return target != null and target.can_accept(_held_type())

# downstream neighbour (re-resolved every frame, no cached reference -- see _neighbour).
# The presentation layer needs it to solve the delivery drop point, so it is exposed as a
# public read-only query.
func get_delivery_target() -> Building:
	return _neighbour(direction)

# type of the item currently in transit (public read-only query: the presentation layer
# solves the downstream drop point and its size by type).
func get_held_type() -> String:
	return _held_type()

# type of the item on the belt: the display bag.item_type is already fixed by _try_extract;
# here we fall back to looking it up from the contents.
func _held_type() -> String:
	if not bag.item_type.is_empty():
		return bag.item_type
	var types: Array[String] = bag.types()
	return types[0] if not types.is_empty() else ""

# get neighbour: re-query every tick, no cached reference -- Map.remove_building clears
# cell.building before queue_free, so a cached reference would dangle.
func _neighbour(in_offset: Vector2i) -> Building:
	if not Level.current or not Level.current.map:
		return null
	var neighbour_cell: Cell = Level.current.map.get_cell(axis + in_offset)
	if not neighbour_cell:
		return null
	return neighbour_cell.building
