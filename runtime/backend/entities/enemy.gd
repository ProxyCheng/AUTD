class_name Enemy
extends Creature

func create_action() -> Action:
	return SequenceAction.new([
		MoveToAction.new(MainBase.current.axis),
		EnemyAttackAction.new(),
	])
