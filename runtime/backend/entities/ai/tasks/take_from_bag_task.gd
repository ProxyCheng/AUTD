class_name TakeFromBagTask
extends BagTransferTask

# 取货叶子:到达源装卸点后,从黑板的 source_bag 取 carry_amount 件,装进工人对应的随身仓。
# 取多少以实际交付数为准(源可能已被并发搬空而少给),供 PutToBagTask 落库。
# 物品类型取黑板 &item_type(搬运任务按需求方声明写入;通配仓的 item_type 为空,靠它才取得到货),
# 为空才回退源仓 item_type(顶岗取工具的老路径不写该键)。
# 入库按物品性质分流:
#   散料 → 头顶仓(head_bag,多类型仓):按源仓类型入库,不动仓里已有的其他类型;
#   有状态单体(工具)→ 手仓(hand_bag,容量 1):held_tool()/供能磨损/归还全读手仓,
#     工具进错仓就等于"人手里没有工具",顶岗只能空手开工(基准 1.0,只是少了工具加成)。
#
# 搬运是**计时**的(见 BagTransferTask):开趟当帧源仓就扣货,跨若干 tick 才进随身仓,
# 故本叶子会返回 RUNNING —— 表现层正是靠这段过程画"物品飞过来"。
#
# 源仓缺失 / 一件都没取到一律返回 FAILURE —— 它只表示"这一步什么都没取到",不是"整个任务失败",
# 由各调用树自行兜底:
#   搬运(transport_haul.tres):FAILURE 经外层 JobRunnerTask 结束本趟、把工人还给调度池;
#   顶岗(man_building.tres):move_tool + take_tool 整对包在 BTSelector[…, BTAlwaysSucceed] 里,
#     取不到就跳过整对、直接空手开工(基准 1.0,只是少了工具加成)。

func _tick(_in_delta: float) -> int:
	var labor := get_agent() as Labor
	if labor == null:
		return BT.Status.FAILURE
	# 已经在搬:等这一批飞完(后端逐件取、逐件交,见 ItemTransfer)。
	if _transfer_id >= 0:
		return await_transfer()
	var bb := get_blackboard()
	# 无类型临时变量先判定有效再赋 typed,避免赋值瞬间遇已 freed 的 bag 即崩。
	var raw_bag: Variant = bb.get_var(TransportTask.BB_SOURCE_BAG, null, false)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_bag) or not (raw_bag is Bag):
		return BT.Status.FAILURE
	var bag: Bag = raw_bag
	# 物品类型优先取黑板(搬运任务按需求方声明写入,通配仓靠它才取得到货);
	# 为空才回退源仓的主要类型(顶岗取工具的老路径不写该键,行为不变)。
	var item_type: String = bb.get_var(TransportTask.BB_ITEM_TYPE, "", false)
	if item_type.is_empty():
		item_type = bag.item_type
	var wanted: int = bb.get_var(TransportTask.BB_CARRY_AMOUNT, 0, false)
	# 入库分流(见文件头):有状态单体进手仓,散料进头顶仓。
	var stateful: bool = Bag.is_stateful(item_type)
	var dest: Bag = labor.hand_bag if stateful else labor.head_bag
	if not is_instance_valid(dest):
		return BT.Status.FAILURE
	# 先把头顶仓的主要类型写上:搬运逐件交付,类型若等整批落地才写,头顶垛会在整批期间一直
	# 按空类型隐藏,直到最后一件才"啪"地全冒出来 —— 与逐件飞行对不上。
	# 头顶仓是多类型仓:主要类型(item_type)只跟着散料走 —— 工具那件不该让头顶携带垛改显示工具
	# (工具由 %tool 那个 ItemStack 专门展示,见 entity_actor)。
	# 解析结果为空时不写:否则会把头顶仓的主要类型抹成空、展示侧随之失去绑定。
	if not stateful and not item_type.is_empty():
		labor.head_bag.item_type = item_type
	if not begin_transfer(bag, dest, item_type, wanted):
		return BT.Status.FAILURE
	return BT.Status.RUNNING
