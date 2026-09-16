class_name PutToBagTask
extends BTAction

# 卸货叶子:到达目标装卸点后,把工人随身仓 carried_bag 中属于目标仓类型的物品实际放入 dest_bag。
# 走 Bag.move_to 逐件搬运(有状态单体搬实例本身、耐久不重置);目标仓装不下的部分留在随身仓,不丢件。

func _tick(_in_delta: float) -> int:
	var bb := get_blackboard()
	# 无类型临时变量先判定有效再赋 typed,避免赋值瞬间遇已 freed 的 bag 即崩。
	var raw_bag: Variant = bb.get_var(TransportTask.BB_DEST_BAG, null, false)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_bag) or not (raw_bag is Bag):
		return BT.Status.FAILURE
	var bag: Bag = raw_bag
	var labor := get_agent() as Labor
	if labor and is_instance_valid(labor.carried_bag):
		# 只卸目标仓自己声明的那类物品:随身仓是多类型仓,count 是各类型总和,
		# 按它落库会把工具等其他类型也一并塞进单类型仓(且工具的实例会被丢弃重建)。
		var carried: Bag = labor.carried_bag
		carried.move_to(bag, bag.item_type, carried.count_of(bag.item_type))
	return BT.Status.SUCCESS
