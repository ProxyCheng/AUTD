class_name ToolDurabilityBar
extends HeadBar

# 手持工具耐久条:值 = 工人手持仓(Labor.tool_bag)里那件工具的耐久占比;
# 无工具 / 满耐久 / 已报废都不显示(与 EntityHealthBar 同约定)。
# 复用 HeadBar 的 billboard 定位、头顶高度测量与显隐;这里只提供值来源与颜色。
# 工具不再是房间实体(见 Labor.tool_bag),故本条挂的是工人 actor,从工人的手持仓取数;
# 与血条同处一个 HeadBarGroup 竖排,不会互相遮挡。逐帧读值,故工具磨损时自动跟随,无需连信号。

const COLOR_TOOL: Color = Color(0.95, 0.72, 0.2)

var labor: Labor = null

func _ready():
	super._ready()
	set_fill_color(COLOR_TOOL)

# 接受任意 Entity;非 Labor(没有 tool_bag)置空,本条自动隐藏。
func configure(in_entity: Entity):
	labor = in_entity as Labor
	if labor == null:
		hide()

func _value() -> float:
	var tool := _held_tool()
	if tool == null:
		return -1.0
	if tool.durability <= 0.0 or tool.durability >= tool.max_durability:
		return -1.0
	return tool.durability_ratio()

# 工人手持仓里那件工具;无 / 已 freed / 非 Tool 时返回 null。
func _held_tool() -> Tool:
	if labor == null or not is_instance_valid(labor.carried_bag):
		return null
	var carrier: Object = labor.carried_bag.peek_state()
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Tool):
		return null
	var tool: Tool = carrier
	return tool
