class_name DepositLoadTask
extends BTAction

# 空闲卸货·落库叶子:走到目标仓装卸点后,把 FindDepositBagTask 规划的那类物品实际搬进仓。
# 工具(有状态单体)走 take_state/add_state 搬实例本身,耐久跟着一起过去,不重置;目标仓
# 此刻被占满则原样放回随身仓(绝不丢件)。散料先算目标仓余量再取 —— remove_count_of 对
# 有状态格是丢弃语义,多取会直接毁件。
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
	if Bag.is_stateful(item_type):
		_deposit_stateful(carried, bag, item_type)
		return BT.Status.SUCCESS
	_deposit_fungible(carried, bag, item_type)
	return BT.Status.SUCCESS

# 有状态单体(工具):搬实例本身(耐久不重置);目标仓满则放回随身仓,绝不丢件。
func _deposit_stateful(in_carried: Bag, in_bag: Bag, in_item_type: String):
	var carrier: Object = in_carried.take_state(in_item_type)
	if carrier == null:
		return
	if not in_bag.add_state(in_item_type, carrier):
		in_carried.add_state(in_item_type, carrier)

# 散料:先算目标仓余量,再取不超过余量的件数(remove_count_of 对有状态格是丢弃语义,
# 超量取会白丢;目标仓装不下的部分留在随身仓)。
func _deposit_fungible(in_carried: Bag, in_bag: Bag, in_item_type: String):
	var room: int = in_bag.max_count - in_bag.count
	var amount: int = mini(room, in_carried.count_of(in_item_type))
	if amount <= 0:
		return
	in_carried.remove_count_of(in_item_type, amount)
	in_bag.add_count_of(in_item_type, amount)
