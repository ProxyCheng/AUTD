class_name Labor
extends Creature

func _init():
	super._init()
	move_speed = 1

# 原 LaborBrain 的注册/注销逻辑内联:进场向调度中心注册,离场注销。
func _ready():
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
