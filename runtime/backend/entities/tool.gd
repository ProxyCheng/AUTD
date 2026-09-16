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
# 工人跨任务一直握着同一件,直到它报废 —— 这样耐久才有意义(放下再取会重置为满)。

const DEFAULT_MAX_DURABILITY: float = 100.0

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

# 本工具对某配方的工作效率倍率:基类 1.0(等同空手),子类按用途覆写(如 Axe 砍树)。
# 配方经 required_tool 声明"需要什么工具",实现方比对自身 type 决定是否生效。
func work_efficiency_for(_in_recipe: RecipeData) -> float:
	return 1.0

# 房间每帧 tick 所有实体(Room.RoomRegion.tick);工具自身无逐帧逻辑,留空以兑现该契约。
func tick(_in_delta: float):
	pass
