class_name PutToBagTask
extends BTAction

# 卸货叶子:到达目标装卸点后,把黑板上 carried_count 件实际放入 dest_bag。
# add_count 自带容量上限截断,目标被占满时放不下部分自然丢弃。

func _tick(_in_delta: float) -> int:
	var bb := get_blackboard()
	# 无类型临时变量先判定有效再赋 typed,避免赋值瞬间遇已 freed 的 bag 即崩。
	var raw_bag: Variant = bb.get_var(TransportTask.BB_DEST_BAG, null, false)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_bag) or not (raw_bag is Bag):
		return BT.Status.FAILURE
	var bag: Bag = raw_bag
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
