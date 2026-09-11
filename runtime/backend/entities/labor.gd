class_name Labor
extends Creature

# 工人随身仓:携带量的唯一来源(供 frontend 头顶表现)。
# 不向 Logistics 注册——它不是物流供需节点,仅随工人存取。
var carried_bag: Bag = null

func _init():
	super._init()
	move_speed = 1

# 原 LaborBrain 的注册/注销逻辑内联:进场向调度中心注册,离场注销。
func _ready():
	carried_bag = Bag.new()
	carried_bag.name = "CarriedBag"
	carried_bag.max_count = Logistics.CARRY_CAPACITY
	add_child(carried_bag)
	carried_bag.owner = owner
	var manager := _get_manager()
	if manager:
		manager.register_labor(self)

func _exit_tree():
	var manager := _get_manager()
	if manager:
		manager.unregister_labor(self)

func create_tree() -> BehaviorTree:
	var manager := _get_manager()
	if manager:
		return manager.request_work(self)
	return super.create_tree()

func _get_manager() -> LaborManager:
	if not Level.current:
		return null
	return Level.current.labor_manager
