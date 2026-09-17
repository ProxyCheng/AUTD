class_name PutToBagTask
extends BagTransferTask

# 卸货叶子:到达目标装卸点后,把工人随身仓中属于目标类型的物品放进 dest_bag。
# 搬运是**计时**的(见 BagTransferTask):开趟当帧随身仓就扣货、货进托管仓飞着,跨若干 tick
# 才落进目标仓,故本叶子会返回 RUNNING —— 表现层正是靠这段过程画"物品飞进料堆"。
# 走的是 §5.8 唯一认可的搬运原语(有状态单体搬实例本身、耐久不重置);目标仓装不下的部分
# 由托管仓退回随身仓,不丢件。
# 物品类型取黑板 &item_type(搬运任务按需求方声明写入;通配仓的 item_type 为空,靠它才放得进),
# 为空才回退目标仓 item_type(老路径不写该键)。
# 货源按物品性质分流(与 TakeFromBagTask 的入库分流对称):
#   散料 → 头顶仓(head_bag);有状态单体(工具)→ 手仓(hand_bag)。
#
# 失败约定(与 TakeFromBagTask 的"没取到就 FAILURE"对称):没能把随身携带的该类物品**全部**放进
# 目标仓(目标满/被并发占满)即 FAILURE —— 由外层 JobRunnerTask 结束本趟、残留留在随身仓
# (不再销毁,见 JobRunnerTask._finish),由工人的下一次空闲窗口或下一份活的 shed 步骤重新入仓。
# 携带量为 0 时视为"卸完了",仍 SUCCESS(空跑不是失败)。

func _tick(_in_delta: float) -> int:
	# 已经在飞:等它落地。此刻货在托管仓里(随身仓已扣、目标仓还没进),别再去解析随身仓。
	# 注意先把 RUNNING 放行 —— await_transfer() 在途时返回的正是 RUNNING,
	# 若写成"非 SUCCESS 即 FAILURE",叶子会在开趟后第一 tick 就失败,工人当场走人、
	# 而搬运仍由 Logistics 跑完(货照飞),看着就是"货没卸完就移动"。
	if _transfer_id >= 0:
		var status: int = await_transfer()
		if status == BT.Status.RUNNING:
			return BT.Status.RUNNING
		if status != BT.Status.SUCCESS:
			return BT.Status.FAILURE
		# 少放了(目标被并发占满,余量退回随身仓)就是本趟没完成,见文件头的失败约定。
		return BT.Status.SUCCESS if delivered() >= moved() else BT.Status.FAILURE
	var bb := get_blackboard()
	# 无类型临时变量先判定有效再赋 typed,避免赋值瞬间遇已 freed 的 bag 即崩。
	var raw_bag: Variant = bb.get_var(TransportTask.BB_DEST_BAG, null, false)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_bag) or not (raw_bag is Bag):
		return BT.Status.FAILURE
	var bag: Bag = raw_bag
	var item_type: String = bb.get_var(TransportTask.BB_ITEM_TYPE, "", false)
	if item_type.is_empty():
		item_type = bag.item_type
	var labor := get_agent() as Labor
	if labor:
		var stateful: bool = Bag.is_stateful(item_type)
		var source: Bag = labor.hand_bag if stateful else labor.head_bag
		if is_instance_valid(source):
			# 只卸解析出的那一类:随身仓是多类型仓,count 是各类型总和,
			# 按它落库会把工具等其他类型也一并塞进单类型仓(且工具的实例会被丢弃重建)。
			var carried: int = source.count_of(item_type)
			if carried <= 0:
				return BT.Status.SUCCESS
			if not begin_transfer(source, bag, item_type, carried):
				return BT.Status.FAILURE
			return BT.Status.RUNNING
	return BT.Status.SUCCESS
