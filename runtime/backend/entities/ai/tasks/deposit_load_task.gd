class_name DepositLoadTask
extends BTAction

# 空闲卸货·落库叶子:走到目标仓装卸点后,把 FindDepositBagTask 规划的那类物品实际搬进仓。
# 搬运一律走 Bag.move_to:工具(有状态单体)搬实例本身,耐久跟着一起过去、不重置;
# 散料按目标仓余量截断,目标仓此刻被占满则留在随身仓(绝不丢件)。
#
# 恒 SUCCESS:空闲树不因"仓满了/东西没了"中断;无处可卸时规划步骤已写成空计划(空跑跳过)。
# 不置 state / 不发信号:空闲期间的 state 归 WanderTask(§5.3 的 frontend state 契约)。

func _tick(_in_delta: float) -> int:
	var bb := get_blackboard()
	var item_type: String = bb.get_var(FindDepositBagTask.BB_DEPOSIT_TYPE, "", false)
	if item_type.is_empty():
		return BT.Status.SUCCESS
	# 无类型临时变量先判定有效再赋 typed,避免赋值瞬间遇已 freed 的 bag 即崩。
	var raw_bag: Variant = bb.get_var(FindDepositBagTask.BB_DEPOSIT_BAG, null, false)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_bag) or not (raw_bag is Bag):
		return BT.Status.SUCCESS
	var bag: Bag = raw_bag
	var labor := get_agent() as Labor
	if labor == null:
		return BT.Status.SUCCESS
	var raw_carried: Variant = labor.carried_bag
	if not is_instance_valid(raw_carried) or not (raw_carried is Bag):
		return BT.Status.SUCCESS
	var carried: Bag = raw_carried
	# 有状态单体一次搬一件(实例本身带走,耐久不重置);散料搬该类型的全部存量,
	# 目标仓余量/随身仓存量的截断与拒收放回都在 move_to 内部完成。
	if Bag.is_stateful(item_type):
		carried.move_to(bag, item_type, 1)
	else:
		carried.move_to(bag, item_type, carried.count_of(item_type))
	return BT.Status.SUCCESS
