class_name ConveyorModel
extends Node3D

# conveyor presentation model (dumb presentation script, no backend logic).
#
# belt surface motion is driven by a skeletal loop animation: 12 cleats are merged into a
# single skinned mesh, one cleat per bone (see ConveyorRig / cleats in conveyor.blend), and
# the ConveyorRig|Run animation is played by %AnimationPlayer.
#
# loop mechanism: one animation cycle travels exactly "one cleat spacing", so after a full
# cycle every cleat lands exactly where the next one was; the 12 cleats are fully identical
# => their pose sets coincide => seamless loop, and the keyframe count is only 1/12 of the
# "travel a whole loop" approach. So this animation must play looping as a whole and cannot
# be played as a one-shot action.
#
# scale: the root node of conveyor.tscn scales the art uniformly to 1 cell (belt surface 1
# cell long, 1 cell wide), so the belt surface's world linear speed must be multiplied by the
# root node scale. Here it is derived from this node's own scale, avoiding a disconnect from
# a second hardcoded scale in the scene.
#
# orientation: the root node is also rotated +90 degrees around Y, aligning the belt travel
# direction (model +X) with the model front (-Z), matching the convention of
# BuildingActor.look_at -- so data.direction is the output direction.
#
# action phases: the backend Conveyor runs two item-handover actions, and both animate the
# item with position/orientation/scale transitioning together (see Trs.arc_lerp):
#   * "delivering": the item is "handed" from the belt exit to the downstream drop point;
#   * "picking": the mirror action, the item is brought from the source pile onto the belt
#     entrance.
# The drop/source pose is solved by BuildingActor and passed in via set_delivery_anchor /
# set_pick_anchor, since this model does not know the neighbouring building (dumb
# presentation, see section 5.5).
#
# node convention (see conveyor.tscn, %AnimationPlayer is already marked
# unique_name_in_owner in the scene):
#   %AnimationPlayer -> ConveyorRig|Run

const ANIM_NAME: StringName = &"ConveyorRig|Run"

# duration of one animation cycle (seconds): 24 frames @24fps on the Blender side.
const CYCLE_SECONDS: float = 1.0

# distance the belt surface travels in "model local space" in one cycle (m): the spacing
# after the 12 cleats evenly divide the loop.
const CYCLE_DISTANCE: float = 0.342124

# baseline belt surface linear speed of the animation in model local space (m/s), i.e. the
# speed when speed_scale = 1.
const ANIM_BASE_SPEED: float = CYCLE_DISTANCE / CYCLE_SECONDS

# default belt surface linear speed (m/s, world space) = 1 cell = 1 unit / backend
# Conveyor.CELL_TRAVEL_SECONDS, i.e. the reciprocal of that constant. Changing the belt
# speed in the backend means changing this too.
const DEFAULT_SPEED: float = 0.5

# player resolved by unique name: comes with the FBX, marked unique_name_in_owner by
# conveyor.tscn.
@onready var _animation: AnimationPlayer = %AnimationPlayer
# payload stack (already in place in conveyor.tscn): shows the in-transit item, sliding
# along the belt surface with progress.
@onready var _hold_stack: ItemStack = $hold_stack

# -- payload geometry (model local space) --
# the belt surface travels along +X in model local space (see the root node scale/rotation
# in conveyor.tscn), so the entrance is on the -X side and the exit on the +X side. The
# values come from the **true ends** of the measured belt surface AABB and must not be inset
# by hand: the ends of two adjacent belts land on the same cell edge in world space, so "A's
# end" and "B's start" only coincide when each uses its own true endpoint -- inset by half an
# item length and the item jumps forward by a whole item length when crossing belts.
const BELT_INPUT_X: float = -0.963258
const BELT_OUTPUT_X: float = 0.986742
const BELT_TOP_Y: float = 0.1877

# desired item length (world units, about 4/5 cell). Native prop sizes vary a lot (arrow vs
# log), and without normalization the log would cover the whole belt while the arrow would be
# invisibly small, so everything is scaled uniformly to this length by type.
const ITEM_LENGTH: float = 0.8

var _bag: Bag = null

# -- delivery action (backend Conveyor's "delivering" phase) --
# the item is "handed" from the belt exit to the downstream drop point, with
# position/orientation/scale all transitioning together (see Trs.arc_lerp). The drop point's
# world pose is solved by BuildingActor and passed in via set_delivery_anchor -- this model
# does not know the downstream building, so it does not have to reach into level to find it
# (dumb presentation, see section 5.5).
var _progress: float = 0.0
var _deliver_progress: float = 0.0
var _delivery_anchor: Transform3D = Transform3D.IDENTITY
var _has_anchor: bool = false

# -- pickup action (backend Conveyor's "picking" phase) --
# the item is brought from the source pile's slot onto the belt entrance, with
# position/orientation/scale all transitioning together (see Trs.arc_lerp). The start pose is
# solved by BuildingActor and passed in via set_pick_anchor -- same reason as the delivery
# anchor: this model does not know the upstream building (dumb presentation, section 5.5).
var _pick_progress: float = 0.0
var _pick_anchor: Transform3D = Transform3D.IDENTITY
var _has_pick_anchor: bool = false

func _ready():
	# the end and start pose sets join (see "loop mechanism" in the file header), so play it
	# looping as a whole with LOOP_LINEAR.
	var animation: Animation = _animation.get_animation(ANIM_NAME)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR
	set_speed(DEFAULT_SPEED)

# set the belt surface linear speed (m/s, world space): converted to playback rate using the
# world-space baseline speed; passing 0 pauses it (cleats stop in place).
# Called by the building Actor after a has_method probe (optional presentation interface,
# same as the state contract of section 5.4).
func set_speed(in_speed: float):
	_animation.speed_scale = in_speed / _world_base_speed()
	if is_zero_approx(in_speed):
		_animation.pause()
	elif not _animation.is_playing():
		_animation.play(ANIM_NAME)

# world-space baseline belt surface speed: the animation's own-space speed x root node scale
# (this scene scales the art to 1 cell).
func _world_base_speed() -> float:
	return ANIM_BASE_SPEED * absf(scale.x)

# bind the backend display bag (= Conveyor.bag, the in-transit item), forwarded by
# BuildingActor (section 5.5). The actor passes null when unbinding.
func bind_bag(in_bag: Bag):
	if is_instance_valid(_bag) and _bag.item_type_changed.is_connected(_on_bound_type_changed):
		_bag.item_type_changed.disconnect(_on_bound_type_changed)
	_bag = in_bag
	_hold_stack.bind(in_bag)
	# bind before connecting: ItemStack itself also connects item_type_changed, so let it
	# rebuild the prop first and change the scale here afterwards.
	if is_instance_valid(_bag) and not _bag.item_type_changed.is_connected(_on_bound_type_changed):
		_bag.item_type_changed.connect(_on_bound_type_changed)
	_normalize_item_scale()
	# pool rebind: both actions' anchors/progress are all invalidated and the item returns to
	# the belt surface pose (prevents pool-reuse residue).
	_has_anchor = false
	_has_pick_anchor = false
	_deliver_progress = 0.0
	_pick_progress = 0.0
	_apply_belt_pose()

# transport progress [0,1]: slide the item along the belt surface from entrance to exit.
# 0 = just picked up (entrance end), 1 = arrived (exit end).
# The travel uses the belt surface's true endpoints (see the BELT_INPUT_X comment) --
# adjacent belts' endpoints coincide on the cell edge, so the item's position is continuous
# when crossing belts and does not jump.
func set_progress(in_progress: float):
	_progress = clampf(in_progress, 0.0, 1.0)
	_apply_belt_pose()

# belt surface rest pose: x interpolates between entrance/exit by progress, y/z and rotation
# are **written in full**. Must be complete: the delivery action has written the whole pose
# via global_transform, so if only x were written here the leftover y/z and rotation would
# remain on the item at the next pickup (item tilted/floating).
func _apply_belt_pose():
	if not is_instance_valid(_hold_stack):
		return
	_hold_stack.position = Vector3(lerpf(BELT_INPUT_X, BELT_OUTPUT_X, _progress), BELT_TOP_Y, 0.0)
	_hold_stack.rotation = Vector3.ZERO

# building state: only used to finish/abort an action phase -- leaving either "delivering" or
# "picking" puts the item back on the belt surface. When it commits to "idle" the item is
# already gone (the stack clears itself), and when it falls back to "blocked" midway progress
# is still 1, so this is exactly the frame where "the item returns to the belt tail and stays
# blocked". The pickup's exit is "working" with progress already 0, so _apply_belt_pose lands
# the item exactly at the belt entrance -- where the pickup animation ends.
func set_state(in_state: String):
	if in_state == "delivering" or in_state == "picking":
		return
	_has_anchor = false
	_has_pick_anchor = false
	_deliver_progress = 0.0
	_pick_progress = 0.0
	_apply_belt_pose()

# delivery drop point (world pose), solved and sent by BuildingActor when entering the
# delivery phase.
func set_delivery_anchor(in_pose: Transform3D):
	_delivery_anchor = in_pose
	_has_anchor = true
	_apply_delivery(_deliver_progress)

# delivery action progress [0,1] (backend Conveyor.deliver_progress): pure sampling, no
# accumulated state, self-consistent on rebind/replay.
func set_deliver_progress(in_progress: float):
	_deliver_progress = clampf(in_progress, 0.0, 1.0)
	_apply_delivery(_deliver_progress)

func _apply_delivery(in_k: float):
	if not _has_anchor or not is_instance_valid(_hold_stack):
		return
	_hold_stack.global_transform = Trs.arc_lerp(_exit_world_pose(), _delivery_anchor, in_k)

# pickup start point (world pose), solved and sent by BuildingActor when entering the pickup phase.
func set_pick_anchor(in_pose: Transform3D):
	_pick_anchor = in_pose
	_has_pick_anchor = true
	_apply_pick(_pick_progress)

# pickup action progress [0,1] (backend Conveyor.pick_progress): pure sampling, no accumulated
# state, self-consistent on rebind/replay.
func set_pick_progress(in_progress: float):
	_pick_progress = clampf(in_progress, 0.0, 1.0)
	_apply_pick(_pick_progress)

func _apply_pick(in_k: float):
	if not _has_pick_anchor or not is_instance_valid(_hold_stack):
		return
	_hold_stack.global_transform = Trs.arc_lerp(_pick_anchor, _entry_world_pose(), in_k)

# the world pose the item should have at a rest point on the belt (in_local_x is
# BELT_INPUT_X or BELT_OUTPUT_X). Recomputed every time, never cached -- still valid on pool
# rebind or on rebinding midway through an action. Deliberately does not read
# _hold_stack.scale: the actions write global_transform, so at that moment it may already be
# scaled (a drop point of "shrink to nothing" shrinks it), and using it as a start point would
# leave the item at the wrong size after an abort.
func _rest_world_pose(in_local_x: float) -> Transform3D:
	var s: float = _normalized_item_scale()
	var item_scale: float = s if s > 0.0 else _hold_stack.scale.x
	var local := Transform3D(Basis.from_scale(Vector3.ONE * item_scale), Vector3(in_local_x, BELT_TOP_Y, 0.0))
	return global_transform * local

func _exit_world_pose() -> Transform3D:
	return _rest_world_pose(BELT_OUTPUT_X)

func _entry_world_pose() -> Transform3D:
	return _rest_world_pose(BELT_INPUT_X)

# item type changed (new item picked up / cleared after delivering) -> re-normalize the size
# by the new type.
func _on_bound_type_changed():
	_normalize_item_scale()

# scale the stack to a uniform world length by the current item type (see ITEM_LENGTH).
# The stack is in the root node's local space and the root node is a uniform scale (see
# conveyor.tscn: the art itself is 1.95 in both length and width, so 1/1.95 compresses it in
# one step to "1 cell long, 1 cell wide"). World length = prop native long axis x stack scale
# x root scale, so divide out the root scale first to derive the local scale the stack should
# use.
# invariant: the art must stay "same scale in length and width", otherwise the root node
# would need a non-uniform scale and items would be stretched sideways.
func _normalize_item_scale():
	if not is_instance_valid(_hold_stack):
		return
	var s: float = _normalized_item_scale()
	if s <= 0.0:
		return
	_hold_stack.scale = Vector3(s, s, s)

# the **rest** local scale the current item should have on the belt surface; unknown type /
# missing model / degenerate root scale -> 0 (meaning "cannot compute").
# The same yardstick as _normalize_item_scale, split out so _exit_world_pose can take the
# rest size -- during the delivery animation _hold_stack.scale has been overwritten and can
# no longer be used as the "rest size".
func _normalized_item_scale() -> float:
	var type: String = _bound_type()
	if type.is_empty() or not ItemStack.ITEM_MODEL_SCENES.has(type):
		return 0.0
	var root_scale: float = absf(scale.x)
	if root_scale <= 0.0:
		return 0.0
	return (ITEM_LENGTH / root_scale) / maxf(ItemStack.long_axis_of(type), 0.0001)

# the type that should currently be shown: prefer the bag's declared item_type (the conveyor
# writes it when it picks up goods), otherwise fall back to the per-item state carrier's type
# -- a stateful item's type is recorded on the carrier and bag.item_type is always empty for
# it (section 5.8).
func _bound_type() -> String:
	if not is_instance_valid(_bag):
		return ""
	if not _bag.item_type.is_empty():
		return _bag.item_type
	var carrier: Object = _bag.peek_state()
	if is_instance_valid(carrier):
		var carrier_type: Variant = carrier.get(&"type")
		if carrier_type is String:
			return str(carrier_type)
	return ""
