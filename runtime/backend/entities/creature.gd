class_name Creature
extends Entity

var health: float = 100
var stored_state: String = ""
var hit_timer: float = 0
var die_timer: float = 0

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
	super.tick(in_delta)

func take_damage(in_damage: Damage):
	health -= in_damage.amount
	if health <= 0:
		die()
		return
	hit_timer = 1
	stored_state = state
	state = "hit"

func die():
	die_timer = 3
	state = "die"

func is_alive() -> bool:
	return state != "die"
