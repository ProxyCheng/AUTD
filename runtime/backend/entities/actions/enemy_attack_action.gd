class_name EnemyAttackAction
extends Action

func enter():
	Level.current.room.remove_entity(entity.id)
