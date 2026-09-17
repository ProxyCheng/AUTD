class_name DepositLoadTask
extends BagTransferTask

# 空闲卸货·落库叶子:走到目标仓装卸点后,把 FindDepositBagTask 规划的那类物品搬进仓
# (散料在头顶仓、工具在手仓,按物品性质分流取源)。
# 搬运是**计时**的(见 BagTransferTask):开趟当帧随身仓就扣货、货进托管仓飞着,跨若干 tick
# 才落进目标仓,故本叶子会返回 RUNNING。走的是 §5.8 唯一认可的搬运原语:工具(有状态单体)
# 搬实例本身,耐久跟着一起过去、不重置;散料按目标仓余量截断,目标仓此刻被占满则由托管仓
# 退回随身仓(绝不丢件)。
#
# 恒 SUCCESS:空闲树不因"仓满了/东西没了"中断;无处可卸时规划步骤已写成空计划(空跑跳过)。
# 不置 state / 不发信号:空闲期间的 state 归 WanderTask(§5.3 的 frontend state 契约)。

func _tick(_in_delta: float) -> int:
	# 已经在飞:等它落地。此刻货在托管仓里(随身仓已扣、目标仓还没进),别再去解析随身仓。
	if _transfer_id >= 0:
		if await_transfer() == BT.Status.RUNNING:
			return BT.Status.RUNNING
		return BT.Status.SUCCESS
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
	# 货源按物品性质分流(与 TakeFromBagTask 的入库分流对称):散料在头顶仓(head_bag),
	# 有状态单体(工具)在手仓(hand_bag)—— 计划卸哪一类,都要能搬得走。
	var stateful: bool = Bag.is_stateful(item_type)
	var raw_carried: Variant = labor.hand_bag if stateful else labor.head_bag
	if not is_instance_valid(raw_carried) or not (raw_carried is Bag):
		return BT.Status.SUCCESS
	var carried: Bag = raw_carried
	# 有状态单体一次搬一件(实例本身带走,耐久不重置);散料搬该类型的全部存量,
	# 目标仓余量/随身仓存量的截断与拒收放回都在 move_to 内部完成。
	var amount: int = 1 if stateful else carried.count_of(item_type)
	begin_transfer(carried, bag, item_type, amount)
	return BT.Status.SUCCESS if _transfer_id < 0 else BT.Status.RUNNING
