class_name Creature
extends Entity

var health: float = 100
var stored_state: String = ""
var hit_timer: float = 0
var die_timer: float = 0

signal damage_taken(Damage)

func tick(in_delta: float):
	if die_timer > 0:
		die_timer -= in_delta
		if die_timer >= 0:
			return
		Level.current.room.remove_entity(id)
		return
	if hit_timer > 0:
		hit_timer -= in_delta
		if hit_timer >= 0:
			return
		in_delta = -hit_timer
		state = stored_state
	return tick_action(in_delta)

func tick_action(in_delta: float):
	var remained_time: float = in_delta
	while remained_time > 0:
		if not action:
			action = create_action()
			add_child(action)
			action.owner = owner
			action.set_entity(self)
		action.enter()
		var action_status: ActionStatus = action.tick(remained_time)
		assert(action_status.remained_time < remained_time, "Loop Detected")
		remained_time = action_status.remained_time
		if not action_status.is_running():
			action.leave()
			remove_child(action)
			action.queue_free()
			action = null

func take_damage(in_damage: Damage):
	health -= in_damage.amount
	if health <= 0:
		die()
		return
	hit_timer = 1
	stored_state = state
	damage_taken.emit(in_damage)
	state = "dizzy"

func die():
	die_timer = 3
	state = "die"

func is_alive() -> bool:
	return state != "die"

func create_action() -> Action:
	return IdleAction.new()
