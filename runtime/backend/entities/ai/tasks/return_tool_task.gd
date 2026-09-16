class_name ReturnToolTask
extends BTAction

# 归还工具叶子:到达归还点后,把工人随身仓里那件工具(有状态单体)挪进黑板 &return_bag。
# 工人干完一份活就把工具还回 Stockpile —— 免得随身仓那一格一直被占着(搬运容量少一件)。
# 工具是"按件"的:这里走 take_state/add_state 搬运实例本身,耐久跟着一起过去,不重置。
#
# 无工具 / 归还仓失效 / 归还仓已满 → 恒 SUCCESS(工具自己留着,不是失败)。

const BB_RETURN_BAG: StringName = &"return_bag"

func _tick(_in_delta: float) -> int:
	var labor := get_agent() as Labor
	if labor == null or not is_instance_valid(labor.carried_bag):
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
	var carrier: Object = labor.carried_bag.take_state(tool.type)
	if carrier == null:
		return BT.Status.SUCCESS
	if not bag.add_state(tool.type, carrier):
		# 归还仓满了:把工具放回自己身上(不丢)
		labor.carried_bag.add_state(tool.type, carrier)
	return BT.Status.SUCCESS

# 随身仓里那件工具;无 / 已 freed / 非 Tool 时返回 null。
func _held_tool(in_labor: Labor) -> Tool:
	var carrier: Object = in_labor.carried_bag.peek_state()
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool
