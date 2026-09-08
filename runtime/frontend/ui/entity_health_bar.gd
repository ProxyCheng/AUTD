class_name EntityHealthBar
extends HeadBar

# 血条:值 = 实体血量占比;按敌我阵营染色;满血/归零不显示。
# 复用 HeadBar 的 billboard 定位、头顶高度测量与显隐;这里只提供值来源与颜色。

const COLOR_ENEMY: Color = Color(0.92, 0.24, 0.2)
const COLOR_FRIENDLY: Color = Color(0.3, 0.85, 0.35)

var creature: Creature = null

# 接受任意 Entity;非 Creature(无 health,如 Arrow)置空血条自动隐藏。
func configure(in_entity: Entity):
	creature = in_entity as Creature
	if creature:
		set_fill_color(COLOR_ENEMY if creature is Enemy else COLOR_FRIENDLY)
	else:
		hide()

func _value() -> float:
	if not creature:
		return -1.0
	if creature.health <= 0.0 or creature.health >= creature.max_health:
		return -1.0
	return creature.health / creature.max_health
