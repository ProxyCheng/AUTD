class_name PutToBagTask
extends BTAction

# 卸货叶子:到达目标装卸点后,把黑板上 carried_count 件实际放入 dest_bag。
# add_count 自带容量上限截断,目标被占满时放不下部分自然丢弃。

func _tick(_in_delta: float) -> int:
	var bb := get_blackboard()
	var bag: Bag = bb.get_var(TransportTask.BB_DEST_BAG, null, false)
	if not bag or not is_instance_valid(bag):
		return BT.Status.FAILURE
	var carried: int = bb.get_var(TransportTask.BB_CARRIED_COUNT, 0, false)
	if carried > 0:
		bag.add_count(carried)
		bb.set_var(TransportTask.BB_CARRIED_COUNT, 0)
	# 卸货完成:清空实体可观察携带状态
	var agent := get_agent() as Creature
	if agent:
		agent.carried_item_type = ""
		agent.carried_count = 0
	return BT.Status.SUCCESS
