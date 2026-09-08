class_name EnemyAttackTask
extends BTAction

# 抵达主基地后的"攻击":接触即摧毁自身(从 Room 移除)。
# 对应旧 EnemyAttackAction;实体随后从 Room 待 tick 列表摘除,树不再被驱动。

func _enter():
	var entity := get_agent() as Entity
	if entity and Level.current:
		Level.current.room.remove_entity(entity.id)

func _tick(_in_delta: float) -> int:
	return BT.Status.SUCCESS
