class_name ReturnToolTask
extends BTAction

# 归还工具叶子:到达归还点后,把工人**手仓**(hand_bag)里那件工具(有状态单体)挪进黑板 &return_bag。
# 工人干完一份活就把工具还回 Stockpile —— 免得手仓那一格一直被占着(手里那件不该长期白拿)。
# 工具是"按件"的:这里走 Bag.move_to 搬实例本身,耐久跟着一起过去,不重置。
#
# 无工具 / 归还仓失效 / 归还仓已满 → 恒 SUCCESS(工具自己留着,不是失败)。

const BB_RETURN_BAG: StringName = &"return_bag"

func _tick(_in_delta: float) -> int:
	var labor := get_agent() as Labor
	if labor == null or not is_instance_valid(labor.hand_bag):
		return BT.Status.SUCCESS
	var tool := _held_tool(labor)
	if tool == null:
		return BT.Status.SUCCESS
	# 无类型临时变量先判定有效再赋 typed,避免赋值瞬间遇已 freed 的 bag 即崩。
	var raw_bag: Variant = get_blackboard().get_var(BB_RETURN_BAG, null, false)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_bag) or not (raw_bag is Bag):
		return BT.Status.SUCCESS
	var bag: Bag = raw_bag
	# 搬实例本身(耐久跟着一起过去,不重置);归还仓满则留在手仓,绝不丢件。
	labor.hand_bag.move_to(bag, tool.type, 1)
	return BT.Status.SUCCESS

# 手仓里那件工具;无 / 已 freed / 非 Tool 时返回 null。
func _held_tool(in_labor: Labor) -> Tool:
	var carrier: Object = in_labor.hand_bag.peek_state()
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool
