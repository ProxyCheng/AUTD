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

# LimboAI 执行状态:一棵树 = 一次任务,树返回非 RUNNING 即本任务结束,
# 下一帧经 create_tree() 请求新树(无"剩余时间溢出"语义)。
var blackboard: Blackboard = Blackboard.new()
var current_tree: BehaviorTree = null
var bt_instance: BTInstance = null

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
		# 眩晕刚好在帧内结束:把多扣的时间还给本次 tick,并恢复被打断前的 state
		in_delta = -hit_timer
		state = stored_state
	return _run_current_tree(in_delta)

# 固定短 tick 驱动当前行为树;结束后立即要下一棵(本帧不再 update)。
func _run_current_tree(in_delta: float):
	if not bt_instance:
		if current_tree == null:
			current_tree = create_tree()
			if current_tree == null:
				return
		bt_instance = current_tree.instantiate(self, blackboard, self, self)
		if bt_instance == null:
			current_tree = null
			return
	var status: int = bt_instance.update(in_delta)
	if status != BT.Status.RUNNING:
		bt_instance = null
		current_tree = null

# 外部(如 LaborManager 派活)直接换掉当前任务树;下一 tick 生效。
func begin_tree(in_tree: BehaviorTree):
	current_tree = in_tree
	bt_instance = null

func create_tree() -> BehaviorTree:
	var tree := BehaviorTree.new()
	tree.set_root_task(IdleTask.new())
	return tree

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
