class_name TakeFromBagTask
extends BTAction

# 取货叶子:到达源装卸点后,从黑板的 source_bag 实际取 carry_amount 件,装进工人对应的随身仓。
# 取多少以实际取出数为准(源可能已被并发搬空而少给),供 PutToBagTask 落库。
# 入库按物品性质分流:
#   散料 → 头顶仓(head_bag,多类型仓):按源仓类型入库,不动仓里已有的其他类型;
#   有状态单体(工具)→ 手仓(hand_bag,容量 1):held_tool()/供能磨损/归还全读手仓,
#     工具进错仓就等于"人手里没有工具",顶岗只能空手开工(见 Tool.EMPTY_HANDED_EFFICIENCY)。
#
# 源仓缺失/一件都没取到时的返回由 optional 决定:
#   false(默认,搬运语义)= FAILURE,由外层 JobRunnerTask 结束本任务归还工人;
#   true(顶岗语义)= SUCCESS 且什么都没取 —— "没有工具就空手干活"不是失败。

# 源仓缺失/空时是否视为成功(见类注释)。
@export var optional: bool = false

func _tick(_in_delta: float) -> int:
	var bb := get_blackboard()
	# 无类型临时变量先判定有效再赋 typed,避免赋值瞬间遇已 freed 的 bag 即崩。
	var raw_bag: Variant = bb.get_var(TransportTask.BB_SOURCE_BAG, null, false)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_bag) or not (raw_bag is Bag):
		return _miss()
	var bag: Bag = raw_bag
	var labor := get_agent() as Labor
	if labor == null:
		return _miss()
	var wanted: int = bb.get_var(TransportTask.BB_CARRY_AMOUNT, 0, false)
	# 入库分流(见文件头):有状态单体进手仓,散料进头顶仓。
	var stateful: bool = Bag.is_stateful(bag.item_type)
	var dest: Bag = labor.hand_bag if stateful else labor.head_bag
	if not is_instance_valid(dest):
		return _miss()
	# 搬运一律走 move_to:有状态单体(工具)搬实例本身、耐久不重置;取多少以实际搬走数为准。
	var taken: int = bag.move_to(dest, bag.item_type, wanted)
	if taken <= 0:
		return _miss()
	# 头顶仓是多类型仓:主要类型(item_type)只跟着散料走 —— 工具那件不该让头顶携带垛改显示工具
	# (工具由 %tool 那个 ItemStack 专门展示,见 entity_actor)。
	if not stateful:
		labor.head_bag.item_type = bag.item_type
	return BT.Status.SUCCESS

# 没取到货时的返回(见 optional)。
func _miss() -> int:
	return BT.Status.SUCCESS if optional else BT.Status.FAILURE
