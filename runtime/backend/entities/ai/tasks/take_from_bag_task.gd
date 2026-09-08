class_name TakeFromBagTask
extends BTAction

# 取货叶子:到达源装卸点后,从黑板的 source_bag 实际取 carry_amount 件。
# 取多少写回黑板 carried_count(源可能已被并发搬空而少给),供 PutToBagTask 落库。
# 一件都没取到(源空了)则 FAILURE,由外层 JobRunnerTask 结束本任务归还工人。

func _tick(_in_delta: float) -> int:
	var bb := get_blackboard()
	var bag: Bag = bb.get_var(TransportTask.BB_SOURCE_BAG, null, false)
	if not bag or not is_instance_valid(bag):
		return BT.Status.FAILURE
	var wanted: int = bb.get_var(TransportTask.BB_CARRY_AMOUNT, 0, false)
	var taken: int = bag.remove_count(wanted)
	bb.set_var(TransportTask.BB_CARRIED_COUNT, taken)
	if taken <= 0:
		return BT.Status.FAILURE
	# 同步实体可观察携带状态(供 frontend 头顶表现)
	var agent := get_agent() as Creature
	if agent:
		agent.carried_item_type = bag.item_type
		agent.carried_count = taken
	return BT.Status.SUCCESS
