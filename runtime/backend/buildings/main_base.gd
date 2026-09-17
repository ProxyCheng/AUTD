class_name MainBase
extends Building

# 主基地:地图的兜底仓库。自带一只仓接受任意物品类型、容量无限。
# 入库优先级最低(DEPOSIT_LAST):搬运工只要有别的可放处,绝不放进基地;
# 出库优先级最高(WITHDRAW_FIRST):任何缺货请求优先从这里取。
# 兜底地位完全由 bag 的声明属性在 Logistics 撮合中自然涌现,不写任何特判。

static var current: MainBase = null

var bag: Bag = null

func _init():
	current = self

func _ready():
	# 仓必须先于劳工创建并注册:劳工下一个 tick 起就可能要把"无处可放"的物品
	# 存进兜底仓,注册晚一步,兜底仓会在撮合中缺席。
	bag = Bag.new()
	bag.name = "Bag"
	bag.item_type = ""
	bag.accepts_any_type = true
	bag.max_count = Bag.UNLIMITED
	# preferred_min_count = 0 是承重墙:基地永不"欠货",Logistics 绝不把它当需求方 ——
	# 无限容量的仓一旦被当需求方,会把全图料堆的库存全部吸进自己嘴里。
	bag.preferred_min_count = 0
	# preferred_max_count = 0:只要基地有存货就始终处于"富余供给"态,成为合法供给源 ——
	# "最高优先级供人取货"正是靠"有货即供给"实现。
	# 注意 preferred_max_count 的初值在 Bag 构造时绑定(bag.gd:50,= 当时的 max_count),
	# 事后改 max_count 不会更新它,故这里必须显式重设。
	bag.preferred_max_count = 0
	bag.deposit_priority = Bag.DEPOSIT_LAST
	bag.withdraw_priority = Bag.WITHDRAW_FIRST
	bag.access_position = Vector2(axis)
	add_child(bag)
	bag.owner = owner
	# 主基地刻意不设 stored_count/capacity 镜像:Building.occupancy_fill 对两者做鸭子判定,
	# 缺失时返回 -1 → 前端隐藏容量条(有限容量条对无限仓库无意义)。
	_register_bag()
	for i in range(20):
		var labor = Entity.create("labor")
		labor.position = Vector2(axis.x, axis.y)
		Level.current.room.add_entity(labor)

# 注销仓是必须而非可选:Logistics.unregister_bag 同时取消途经该仓的在途搬运任务,
# 主基地拆除(建筑销毁)时残留任务会指向已失效的仓。
func _exit_tree():
	_unregister_bag()

func get_display_bag() -> Bag:
	return bag

# 主基地是地图的兜底仓库,且 MainBase.current 是 Enemy 每帧读取的 static 引用:
# 在游戏内检视面板里删除它会造成悬空引用并破坏围城逻辑,故禁止游戏内删除。
func is_removable() -> bool:
	return false

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
