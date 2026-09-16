class_name BagItem
extends RefCounted

# 仓内一格:同一类型的若干件。
#   * 无状态散料(原木/石头/箭/炮弹…):只记 item_type + count,同类型合并成一格;
#   * 有状态物品(工具耐久、未来的保鲜度…):count 恒 1,state 指向该件自己的状态载体
#     (工具 = Tool 实例),状态随件保存在仓里。
# 加一种带状态的新物品只需写一个新的载体类 + 给仓配 state_factory,Bag 与物流不必改。

var item_type: String = ""
var count: int = 0
# 该件的状态载体(散料为 null);Bag 只当它是不透明引用,不解读其内容。
var state: Object = null

static func make_fungible(in_item_type: String, in_amount: int) -> BagItem:
	var entry := BagItem.new()
	entry.item_type = in_item_type
	entry.count = in_amount
	return entry

static func make_stateful(in_item_type: String, in_state: Object) -> BagItem:
	var entry := BagItem.new()
	entry.item_type = in_item_type
	entry.count = 1
	entry.state = in_state
	return entry

# 本格是否带按件状态(有状态物品)。
func has_state() -> bool:
	return state != null
