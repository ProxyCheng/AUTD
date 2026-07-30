class_name Enemy
extends Entity

var die_timer: float = 0

func create_action() -> Action:
	return SequencialAction.new([
		MoveToAction.new(MainBase.current.axis),
		EnemyAttackAction.new(),
	])
