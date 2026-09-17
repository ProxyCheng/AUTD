class_name EntityHealthBar
extends HeadBar

# 血条:值 = 实体血量占比;按敌我阵营染色;满血/归零不显示。
# 复用 HeadBar 的 billboard 定位、头顶高度测量与显隐;这里只提供值来源与颜色。

const COLOR_ENEMY: Color = Color(0.92, 0.24, 0.2)
const COLOR_FRIENDLY: Color = Color(0.3, 0.85, 0.35)

var creature: Creature = null

# 接受任意 Entity;非 Creature(无 health,如 Ballistic)置空血条自动隐藏。
func configure(in_entity: Entity):
	creature = in_entity as Creature
	if creature:
		set_fill_color(color_for(creature))
	else:
		hide()

# 阵营配色:敌对红 / 友方绿。检视面板的血条也走这里取色,
# 保证同一生物在世界悬浮条与面板条上颜色一致(单一配色来源)。
static func color_for(in_creature: Creature) -> Color:
	return COLOR_ENEMY if in_creature is Enemy else COLOR_FRIENDLY

func _value() -> float:
	if not creature:
		return -1.0
	if creature.health <= 0.0 or creature.health >= creature.max_health:
		return -1.0
	return creature.health / creature.max_health
