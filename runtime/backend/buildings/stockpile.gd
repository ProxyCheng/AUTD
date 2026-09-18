class_name Stockpile
extends Building

# 料堆:单格仓库。底盘(围栏)内只存放一种物品,item_type 可配置/空仓可更换。
# 存量走料堆专属可观察属性(stored_count),不走 Building.progress——progress
# 保留给"状态进度"(蓄力/冷却等过程量)语义。frontend model 据 stored_count/capacity
# 显示堆叠物品。
# 库存语义接入 logistics:preferred_min = 0 → 自身永不求补货;preferred_max = 容量 →
# 仓储型,不留底、随时可取(有货即可被劳工/传送带搬走),同时因 count 未到 preferred_max
# 而成为落库优先级最高的一层,可随时存入 —— 即"可存可取"的中转仓。
# (判据见 Bag.is_pure_demand / surplus_of;preferred_max 取满才不会被当成"只出不进"。)

const CAPACITY: int = 50
const PREFERRED_MIN_COUNT: int = 0
const PREFERRED_MAX_COUNT: int = CAPACITY
# 默认物品。仅当其有对应 frontend 物品模型时才可显示堆叠;其余类型无模型则暂不显示。
const DEFAULT_ITEM_TYPE: String = "arrow"
# 放置即满仓(原型期用于直接观察堆叠/作为初始弹药补给)。
# 待"生产/搬运"物流链路接入后置 false,由调度系统按需填仓。
const AUTO_FILL_ON_PLACE: bool = true
# 放置时填充的数量。调试期取 1:便于观察"一支箭被搬走 → 上弦 → 射出"的完整链路。
const AUTO_FILL_COUNT: int = 1

var bag: Bag = null

# 当前存放的物品类型(派生自 bag.item_type;空仓时可更换)。
var content_type: String:
	get:
		return bag.item_type if bag else DEFAULT_ITEM_TYPE
signal content_type_changed()

# 料堆容量(只读,供 frontend 归一化显示)
var capacity: int = CAPACITY:
	get:
		return capacity

# 存量镜像(bag.count 的对外可观察副本)。setter 只由内部 _sync_stored_count 驱动。
var stored_count: int = 0:
	get:
		return stored_count
	set(in_count):
		if in_count == stored_count:
			return
		stored_count = in_count
		stored_count_changed.emit()
signal stored_count_changed()

func _ready():
	bag = Bag.new()
	bag.name = "Bag"
	bag.item_type = DEFAULT_ITEM_TYPE
	bag.max_count = CAPACITY
	bag.preferred_min_count = PREFERRED_MIN_COUNT
	bag.preferred_max_count = PREFERRED_MAX_COUNT
	bag.access_position = Vector2(axis)
	add_child(bag)
	bag.owner = owner
	bag.count_changed.connect(_sync_stored_count)
	bag.item_type_changed.connect(_on_bag_item_type_changed)
	_register_bag()
	if AUTO_FILL_ON_PLACE:
		bag.add_count(AUTO_FILL_COUNT)
	_sync_stored_count()

func _exit_tree():
	_unregister_bag()

# 更换存储物品:仅空仓时允许(换品需先清空)。失败返回 false。
func set_content_type(in_type: String) -> bool:
	if in_type == content_type:
		return true
	if stored_count > 0:
		return false
	bag.item_type = in_type
	return true

# 入库/出库入口,返回实际生效数量。
# 注意语义:这是"凭空造件/凭空销毁"的原语(入库造新件、出库丢弃),**不是搬运** ——
# 仓间搬物品必须走 Bag.move_to(搬实例本身,有状态物品的耐久等按件状态才不会被重置)。
func store(in_count: int) -> int:
	if not bag:
		return 0
	return bag.add_count(in_count)

func take(in_count: int) -> int:
	if not bag:
		return 0
	return bag.remove_count(in_count)

func is_full() -> bool:
	return stored_count >= CAPACITY

# bag.count 变化 → 同步镜像属性,经 setter 触发 stored_count_changed
func _sync_stored_count():
	stored_count = bag.count if bag else 0

func get_display_bag() -> Bag:
	return bag

# 单仓建筑:名下唯一的仓就是可搬运的那只。
func get_transfer_bags() -> Array[Bag]:
	var bags: Array[Bag] = [bag]
	return bags

# bag.item_type 变化 → 转发为 content_type_changed(供 UI/表现)。
func _on_bag_item_type_changed():
	content_type_changed.emit()

func _register_bag():
	var logistics: Logistics = _get_logistics()
	if logistics:
		logistics.register_bag(bag)

func _unregister_bag():
	var logistics: Logistics = _get_logistics()
	if logistics:
		logistics.unregister_bag(bag.id)

func _get_logistics() -> Logistics:
	if not Level.current:
		return null
	return Level.current.logistics
