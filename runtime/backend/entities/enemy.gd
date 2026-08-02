class_name Enemy
extends Creature

func create_action() -> Action:
	return SequencialAction.new([
		MoveToAction.new(MainBase.current.axis),
		EnemyAttackAction.new(),
	])
