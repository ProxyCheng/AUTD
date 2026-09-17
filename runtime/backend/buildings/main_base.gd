class_name MainBase
extends Building

# 主基地:地图的中央仓库。中央仓的全部语义(通配任意类型、容量无限、双 FIRST 优先级)
# 收在 MainBaseBag 一处声明;枢纽地位完全由 bag 的声明属性在 Logistics 撮合中自然涌现,
# 不写任何特判。

static var current: MainBase = null

var bag: Bag = null

func _init():
	current = self

func _ready():
	# 仓必须先于劳工创建并注册:劳工下一个 tick 起就可能要把"无处可放"的物品
	# 存进兜底仓,注册晚一步,兜底仓会在撮合中缺席。
	bag = MainBaseBag.new()
	bag.name = "Bag"
	bag.access_position = Vector2(axis)
	add_child(bag)
	bag.owner = owner
	# 初始库存必须在 _register_bag() 之前入仓:Logistics 在注册那一刻就按仓内现状做撮合;
	# 注册后补货会让首轮撮合看到空基地。
	# 必须走 add_count_of 而不是 add_count / 手工塞格:有状态物品(工具)在 Bag._store 里逐件造载体、
	# 每件各占一格 —— 3 把斧头会成为 3 个各自带耐久的独立实例,而不是叠成一格;
	# Bag.default_state_factory 按类型名探 res://runtime/backend/entities/<type>.gd 认出
	# "axe"/"pickaxe",无需给本仓另配 state_factory。
	if data:
		for item_type: String in data.initial_items:
			var amount: int = data.initial_items[item_type]
			if amount > 0:
				bag.add_count_of(item_type, amount)
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
