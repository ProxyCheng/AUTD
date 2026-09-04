class_name Creature
extends Entity

var max_health: float = 100
var health: float = 100:
	get:
		return health
	set(in_health):
		if is_equal_approx(in_health, health):
			return
		health = in_health
		health_changed.emit()
signal health_changed()
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
		# 已知崩溃场景(2026-09 MCP 运行验证发现):敌人被箭矢命中 → take_damage →
		# hit_timer 眩晕恢复后 resume 原 Action,若其 tick 返回 running 且
		# remained_time 未递减会命中本断言使游戏卡死。疑似方向:眩晕打断/恢复时
		# 未正确保留 action 运行上下文。修复前不要把该场景当作正常路径。
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
