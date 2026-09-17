class_name TransportTask
extends LaborTask

# 搬运任务:派一名劳工把 in_amount 件 in_item_type 物品从源 bag 的装卸点搬到目标 bag 的装卸点。
# 单趟携带量由 Logistics.CARRY_CAPACITY 限定,更大的缺货会被 Logistics 拆成多趟。
# 行为逻辑走共享树 transport_haul.tres(先走到源装卸点取货,再走到目标装卸点卸货),
# 参数经工人黑板传递:&source_bag / &dest_bag / &carry_amount / &item_type。
# 树内的 TakeFromBagTask / PutToBagTask 在到达时实际 remove/add(自带上下限截断),
# 故即使源被并发搬空或目标被占满,也不会出现负数或超容。

const HAUL_TREE: BehaviorTree = preload("res://runtime/backend/entities/ai/transport_haul.tres")

const BB_SOURCE_BAG: StringName = &"source_bag"
const BB_DEST_BAG: StringName = &"dest_bag"
const BB_CARRY_AMOUNT: StringName = &"carry_amount"
# 本次搬运的物品类型:通配仓(accepts_any_type)的 item_type 为空,类型必须显式传递,
# 否则 move_to 会因空类型一件都搬不动却仍报成功(取/放叶子据此键解析,见二者实现)。
const BB_ITEM_TYPE: StringName = &"item_type"
# 树内两段移动各自独立的落位目标键(先到源装卸点取,再到目标装卸点放)
const BB_TAKE_ACCESS: StringName = &"take_access"
const BB_PUT_ACCESS: StringName = &"put_access"

var source_bag: Bag = null
var dest_bag: Bag = null
var amount: int = 0
# 本次搬运的物品类型(由 Logistics 按需求方声明给出,见 BB_ITEM_TYPE)。
var item_type: String = ""

func _init(in_source_bag: Bag, in_dest_bag: Bag, in_amount: int, in_item_type: String):
	# 优先级取目标 bag 声明的 transport_priority(请求方定义其补货紧急度)。
	# 默认普通搬运;攻击建筑(如 Crossbow 弹药箱)设为更高档,保证供弹不被普通物流挤占。
	super(1, in_dest_bag.transport_priority)
	source_bag = in_source_bag
	dest_bag = in_dest_bag
	amount = in_amount
	item_type = in_item_type
	# 就近调度锚点取源装卸点(先走去取货)
	anchor_position = in_source_bag.access_position

func make_tree(in_labor: Labor) -> BehaviorTree:
	in_labor.blackboard.set_var(BB_SOURCE_BAG, source_bag)
	in_labor.blackboard.set_var(BB_DEST_BAG, dest_bag)
	in_labor.blackboard.set_var(BB_CARRY_AMOUNT, amount)
	in_labor.blackboard.set_var(BB_ITEM_TYPE, item_type)
	in_labor.blackboard.set_var(BB_TAKE_ACCESS, source_bag.access_position)
	in_labor.blackboard.set_var(BB_PUT_ACCESS, dest_bag.access_position)
	return HAUL_TREE
