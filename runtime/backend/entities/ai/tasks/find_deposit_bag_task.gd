class_name FindDepositBagTask
extends BTAction

# 空闲卸货·规划叶子:工人闲置时,从**两只随身仓**里挑一类"现在用不上"的物品 —— 头顶仓
# (head_bag)的散料残留、手仓(hand_bag)那件工具都算 —— 找一只最近且收得下的已注册仓,
# 把卸货计划写进黑板(供后续 MoveToTargetTask / DepositLoadTask 执行)。
#
# "用不上"的判定:
#   有状态工具 —— 看**持有期间有没有被用上**(Tool.unused_time):刚用完的留着(机器多半马上
#     再来派活,免得每件都往返容器数格),一直没派上用场的才放回去;
#   散料 —— 没有"在用"概念,闲置即可卸。
# 曾经用"上一台机器还要不要这件工具"(黑板 &work_building)来判定,已废弃:机器可能永远不再
# 雇这个工人(输出仓满了/换配方/派给了别人),那样工具会一直卡在游荡的工人手上,而全图的仓里
# 反而没有它 —— 本机派来的新工人只能空手开工(效率差 20 倍,见 Tool.EMPTY_HANDED_EFFICIENCY)。
# 本叶由空闲树周期性重跑(WanderTask 跑满 duration 后让出、整棵树重建),所以"用不上"会被反复检查。
#
# FAILURE = 本叶无活可干:不是 Labor / 身上没有可卸之物 / 全图没有收得下的同类型仓。
# 这不是"任务失败",而是"这一步无事可做" —— 由 shed_load.tres 里包住本叶的 BTSelector 接住:
# 卸货链(BTSequence)整体失败即整条跳过,落到兜底的 BTAlwaysSucceed,主序列照常往下走。
# 正因有 Selector 兜底,本叶才不必谎报 SUCCESS;黑板键也**只在 SUCCESS 时写入**,
# 后续两叶(MoveToTargetTask / DepositLoadTask)只在"确实要卸"时才被执行,无需再各自识别空计划。
#
# 黑板契约(仅 SUCCESS 时写入):
#   &deposit_type   : String  要卸的物品类型(非空)
#   &deposit_bag    : Bag     目标仓(非 null)
#   &deposit_access : Vector2 目标仓装卸点,工人须先走到那里再搬

const BB_DEPOSIT_TYPE: StringName = &"deposit_type"
const BB_DEPOSIT_BAG: StringName = &"deposit_bag"
const BB_DEPOSIT_ACCESS: StringName = &"deposit_access"

func _tick(_in_delta: float) -> int:
	var agent := get_agent() as Entity
	var labor := agent as Labor
	if labor == null:
		return BT.Status.FAILURE
	var shed_type: String = _pick_shed_type(labor)
	if shed_type.is_empty():
		return BT.Status.FAILURE
	var target: Bag = _find_target_bag(shed_type, agent.position)
	if target == null:
		# 全图没有收得下的同类型仓:留着(占一格),等有仓收得下时再卸。
		return BT.Status.FAILURE
	_plan(shed_type, target)
	return BT.Status.SUCCESS

# 挑工人身上第一类"现在用不上"的物品(见文件头):先看头顶仓的散料(闲置即可卸,没有留存理由),
# 再看手仓那件工具(按"持有太久没被用上"判定,刚用过的留着等机器再来派活)。
func _pick_shed_type(in_labor: Labor) -> String:
	var head_type: String = _pick_from_bag(in_labor.head_bag)
	if not head_type.is_empty():
		return head_type
	return _pick_from_bag(in_labor.hand_bag)

# 从一只仓里挑第一类"现在用不上"的物品:有状态工具看"持有太久没被用上",散料闲置即可卸。
func _pick_from_bag(in_bag: Bag) -> String:
	if not is_instance_valid(in_bag):
		return ""
	for item_type: String in in_bag.types():
		var carrier: Object = in_bag.peek_state(item_type)
		# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
		if is_instance_valid(carrier) and carrier is Tool:
			var tool: Tool = carrier
			if not tool.is_unused_too_long():
				continue
		return item_type
	return ""

# 最近的"同类型且收得下"的已注册仓(只读查询,见 Logistics.find_nearest_bag);
# 以工人当前位置为距离原点,故挑的是最近的一只。
func _find_target_bag(in_item_type: String, in_from: Vector2) -> Bag:
	if not Level.current or not Level.current.logistics:
		return null
	return Level.current.logistics.find_nearest_bag(in_item_type, in_from, false)

# 写卸货计划:行走点取目标仓装卸点(工人须先走到那里再搬)。
func _plan(in_item_type: String, in_bag: Bag):
	var bb := get_blackboard()
	bb.set_var(BB_DEPOSIT_TYPE, in_item_type)
	bb.set_var(BB_DEPOSIT_BAG, in_bag)
	bb.set_var(BB_DEPOSIT_ACCESS, in_bag.access_position)
