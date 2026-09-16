class_name FindDepositBagTask
extends BTAction

# 空闲卸货·规划叶子:工人闲置时,从随身仓里挑一类"现在用不上"的物品,找一只最近且
# 收得下的已注册仓,把卸货计划写进黑板(供后续 MoveToTargetTask / DepositLoadTask 执行)。
#
# "用不上"的判定靠黑板 &work_building(ManBuildingTask 派活时写入,跨任务保留,即
# "我上次在哪台机器干活"):该机器仍在、其当前配方还要这件工具 → 留着别卸。这道闸是必须的 ——
# 工人每做完一件都会短暂空闲(Workshop._maintain_manning 要等 _manned_timer 衰减后才重新下单),
# 若此时把斧头卸了,下一单又得走回容器取,来回数格的路比斧头省下的砍伐时间还长。
# 机器无可行配方(active_recipe == null,如输出仓满)时工具不再需要,照卸不误。
#
# 恒 SUCCESS:无可卸 / 全图无处可收都只是"不卸",不是失败。
#
# 黑板契约:
#   &deposit_type   : String  要卸的物品类型;"" = 无物可卸
#   &deposit_bag    : Bag     目标仓;无物可卸 / 无处可收时为 null
#   &deposit_access : Vector2 目标仓装卸点;无物可卸时写工人自身位置(后续移动步骤原地即刻达成)

const BB_DEPOSIT_TYPE: StringName = &"deposit_type"
const BB_DEPOSIT_BAG: StringName = &"deposit_bag"
const BB_DEPOSIT_ACCESS: StringName = &"deposit_access"

func _tick(_in_delta: float) -> int:
	var agent := get_agent() as Entity
	var labor := agent as Labor
	# 无类型临时变量先判定有效再赋 typed,避免赋值瞬间遇已 freed 的 bag 即崩。
	var raw_carried: Variant = labor.carried_bag if labor else null
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_carried) or not (raw_carried is Bag):
		_plan_nothing(agent)
		return BT.Status.SUCCESS
	var carried: Bag = raw_carried
	if carried.count <= 0:
		_plan_nothing(agent)
		return BT.Status.SUCCESS
	var shed_type: String = _pick_shed_type(carried)
	if shed_type.is_empty():
		_plan_nothing(agent)
		return BT.Status.SUCCESS
	var target: Bag = _find_target_bag(shed_type, agent.position)
	if target == null:
		# 全图没有收得下的同类型仓:留着(占一格),等有仓收得下时再卸。
		_plan_nothing(agent)
		return BT.Status.SUCCESS
	_plan(agent, shed_type, target)
	return BT.Status.SUCCESS

# 挑随身仓里第一类"现在用不上"的物品:配方还要用的那类工具跳过,其余(别的工具/散料)都可卸。
func _pick_shed_type(in_carried: Bag) -> String:
	var needed_tool: String = _needed_tool()
	for item_type: String in in_carried.types():
		if item_type == needed_tool:
			continue
		return item_type
	return ""

# 工人"还要用"的工具类型:黑板 &work_building 仍有效、其当前配方要工具时取该类型,否则 ""。
# 机器无可行配方(active_recipe == null,如输出仓满/换配方)即视为不再需要,其工具可卸。
func _needed_tool() -> String:
	var raw_building: Variant = get_blackboard().get_var(ProvideWorkloadTask.BB_BUILDING, null, false)
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(raw_building) or not (raw_building is Workshop):
		return ""
	var building: Workshop = raw_building
	var recipe: RecipeData = building.active_recipe
	if recipe == null:
		return ""
	return recipe.required_tool

# 最近的"同类型且收得下"的已注册仓(只读查询,见 Logistics.find_nearest_bag);
# 以工人当前位置为距离原点,故挑的是最近的一只。
func _find_target_bag(in_item_type: String, in_from: Vector2) -> Bag:
	if not Level.current or not Level.current.logistics:
		return null
	return Level.current.logistics.find_nearest_bag(in_item_type, in_from, false)

# 写"不卸"计划:类型空、仓 null,行走点落回工人自身位置(移动步骤原地即刻达成)。
func _plan_nothing(in_agent: Entity):
	_plan(in_agent, "", null)

# 写卸货计划:有仓时行走点取该仓装卸点(工人须先走到那里再搬);无物可卸时落回自身位置。
func _plan(in_agent: Entity, in_item_type: String, in_bag: Bag):
	var access: Vector2 = in_agent.position if in_agent else Vector2.ZERO
	if in_bag:
		access = in_bag.access_position
	var bb := get_blackboard()
	bb.set_var(BB_DEPOSIT_TYPE, in_item_type)
	bb.set_var(BB_DEPOSIT_BAG, in_bag)
	bb.set_var(BB_DEPOSIT_ACCESS, access)
