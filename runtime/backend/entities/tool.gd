class_name Tool
extends Entity

# 手持工具基类:工人可持用的一类道具实体(斧/镐/锄/铲/剑…)。
# 工具是无生命值的静态物品,故直接 extends Entity 而非 Creature —— 不参与受击/死亡,
# 也不跑行为树。由车间按配方产出(见 CraftingWorkshop),具体工具子类(如 Axe)只声明
# 自身差异,同族通用约定集中在此。
#
# 与表现层的契约:模型由前端按 type 装载(§5.5 的 EntityActor / §8 清单),本类不持有
# 任何视觉引用(§1 前后端分离);本类也不引用音频(§5.7)。
#
# 耐久:容器(Bag)只存可计数的"类型 + 数量",取出时实例化一件(见 Labor.equip_tool),
# 因此耐久是"按件"的;占比经 durability_changed 广播,由前端 ToolDurabilityBar 显示。
# 工人跨任务握着同一件(工具在仓间搬来搬去都走 Bag.move_to,实例与耐久一路跟着走、不重置);
# 一直没派上用场的会被空闲树放回仓里(见 UNUSED_PUT_AWAY_SECONDS)。

const DEFAULT_MAX_DURABILITY: float = 100.0
# 空手注入倍率:配方需要工具而工人手上没有时的效率系数(见 ProvideWorkloadTask._tool_factor)。
# 空手仍能干活,只是极慢;配方本就不需要工具时不受此影响(恒 1.0)。
const EMPTY_HANDED_EFFICIENCY: float = 0.1

var max_durability: float = DEFAULT_MAX_DURABILITY
# 当前耐久,恒被夹在 [0, max_durability];归零即报废(见 is_broken)。
var durability: float = DEFAULT_MAX_DURABILITY:
	get:
		return durability
	set(in_durability):
		var clamped := clampf(in_durability, 0.0, max_durability)
		if is_equal_approx(clamped, durability):
			return
		durability = clamped
		durability_changed.emit()
signal durability_changed()

# 每注入 1 单位工作量消耗的耐久点;<= 0 表示本工具不磨损(子类按用途调整)。
var wear_per_workload: float = 1.0

# "持有但一直没被用上"的时长(秒):工人每 tick 推进它,工具真正驱动工作时清零(见 mark_used)。
# 超过 UNUSED_PUT_AWAY_SECONDS 即视为用不上,工人空闲时把它放回仓里(见 FindDepositBagTask)。
# 为什么按时长判定、而不是"上一台机器还要不要它":机器可能永远不再雇这个工人(输出仓满了、
# 换了配方、派给了别人),那种判定会把工具一直卡在游荡的工人手上,全图的仓里反而没有它。
var unused_time: float = 0.0

# 持有超过这么久没被用上,就放回仓里。取值只需盖过"同一台机器两件活之间的短暂空闲"
# (Workshop._maintain_manning 等 _manned_timer 衰减,约 0.2 秒),所以几秒足够。
const UNUSED_PUT_AWAY_SECONDS: float = 5.0

# 本工具刚驱动过一次工作(由 ProvideWorkloadTask 调用):重置未使用计时。
func mark_used():
	unused_time = 0.0

# 是否已"持有太久没被用上"(空闲树据此决定放回仓里)。
func is_unused_too_long() -> bool:
	return unused_time >= UNUSED_PUT_AWAY_SECONDS

# 耐久占比 [0,1](§5.4 契约:数据层恒输出归一化值,到条宽/动画的换算留给前端)。
func durability_ratio() -> float:
	if max_durability <= 0.0:
		return 0.0
	return durability / max_durability

func is_broken() -> bool:
	return durability <= 0.0

# 磨损 in_amount 点;返回 true 表示因此报废(调用方据此丢弃工具)。
func wear(in_amount: float) -> bool:
	durability -= in_amount
	return is_broken()

# 按注入的工作量磨损;返回 true = 报废。不磨损的工具恒返回 false。
func wear_for_workload(in_workload: float) -> bool:
	if wear_per_workload <= 0.0 or in_workload <= 0.0:
		return false
	return wear(in_workload * wear_per_workload)

# 本工具对某配方的工作效率倍率:基类 1.0(即工具本身不放大注入量;空手基准见 EMPTY_HANDED_EFFICIENCY),
# 子类按用途覆写(如 Axe 砍树)。
# 配方经 required_tool 声明"需要什么工具",实现方比对自身 type 决定是否生效。
func work_efficiency_for(_in_recipe: RecipeData) -> float:
	return 1.0

# 房间每帧 tick 所有实体(Room.RoomRegion.tick);工具自身无逐帧逻辑,留空以兑现该契约。
func tick(_in_delta: float):
	pass
