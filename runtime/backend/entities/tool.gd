class_name Tool
extends Entity

# 手持工具基类:工人可持用的一类道具实体(斧/镐/锄/铲/剑…)。
# 工具是无生命值的静态物品,故直接 extends Entity 而非 Creature —— 不参与受击/死亡,
# 也不跑行为树。由车间按配方产出(见 CraftingWorkshop),具体工具子类(如 Axe)只声明
# 自身差异,同族通用约定集中在此。
#
# 与表现层的契约:模型由前端按 type 装载(§5.5 的 EntityActor / §8 清单),本类不持有
# 任何视觉引用(§1 前后端分离);本类也不引用音频(§5.7)。
