class_name Conveyor
extends Building

# 传送带:单格、单件在途缓存。每 tick 从"输入端"(axis - direction)的邻建取一件,
# 在带面上走 CELL_TRAVEL_SECONDS 秒,再投给"输出端"(axis + direction)的邻建;
# 投不出去就卡住(state = "blocked")并每帧重试 —— 一件没送走就不再取下一件,
# 故整条线是阻塞式的(像 Factorio 的传送带,满了就往回堵)。
#
# direction 来自 BuildingData.direction(网格向量,模型正面 -Z 朝它)= 输出方向;
# 于是输入端 = axis - direction、输出端 = axis + direction。玩家用
# rotate_building_left / rotate_building_right 在放置时步进 90°(见 BuildingMode)。
#
# 取/送都走 Building 的搬运能力接口(provide_to / accept_from),与工人搬运共用同一套
# Bag 判据:料堆这类"可存可取"的仓储型能被取,车间输入仓(纯需求方)不会被抽走。
# 输出端可以是另一个传送带 —— 它的在途缓存经 get_transfer_bags 暴露,未满即可收。
#
# 表现契约(§5.4):
#   state    "idle"(空载待取)/ "working"(在途)/ "blocked"(投不出去,卡住)
#   progress [0,1] 在途进度,0 = 刚取到、1 = 该投送;到站后停在 1 直到投出去
#   承载物挂在自身 bag 上,frontend 经 get_display_bag() 镜像(§5.5)

# 一件物品通过一格所需时间(秒)。与 ConveyorModel.DEFAULT_SPEED(= 1.0 m/s,一格 1 单位)
# 对齐:带面横条与物品同速。改了这里要同步改那个常量。
const CELL_TRAVEL_SECONDS: float = 1.0

# 在途缓存容量:一次只运一件。
const CAPACITY: int = 1

# 在途缓存。刻意**不注册 Logistics** —— 它只是传送带的内部缓冲,不是物流的供需节点;
# 注册了会被当成取货源/落库点,和传送带自己的取送逻辑打架。
var bag: Bag = null

# 在途剩余时间(秒);> 0 表示带上有货且在走。
var _travel_left: float = 0.0

func _ready():
	bag = Bag.new()
	bag.name = "Bag"
	bag.max_count = CAPACITY
	# 通配:传送带不限货物类型,空载时 item_type 为空 —— 若不设通配,can_accept(任意类型)
	# 会因类型不匹配而为假,下游就永远收不下货(串接直接断)。
	bag.accepts_any_type = true
	# 只进不出:在途仓只接受上游**推进来**的货,绝不被别的传送带当货源抽走。否则下游会在
	# 上游刚取到货的同一帧把它"吸"过去 —— 货物等于瞬移,上游那段带面白走,流向也乱。
	# 本带自己投送走的是 Bag.move_to(不经 can_provide),故不受影响。
	bag.preferred_min_count = CAPACITY
	bag.preferred_max_count = CAPACITY
	# cell 由 Map.place_building 在 add_child 之前注入,故 _ready 里可用;
	# 测试中手工 new、不挂到格子上的场合退回原点。
	bag.access_position = Vector2(axis) if cell else Vector2.ZERO
	add_child(bag)
	bag.owner = owner
	bag.count_changed.connect(_on_hold_changed)

# 承载物交给 frontend 镜像(ItemStack),见 §5.5。
func get_display_bag() -> Bag:
	return bag

# 在途缓存参与搬运:别的传送带(或建筑能力接口)据此把货投进来 —— 未满即可收。
# 注意这只影响 Building 的能力接口,Logistics 看不见它(本仓未注册)。
func get_transfer_bags() -> Array[Bag]:
	var bags: Array[Bag] = [bag]
	return bags

func tick(in_delta: float):
	if not bag:
		return
	if bag.count <= 0:
		_try_extract()
		return
	_travel_left = maxf(_travel_left - in_delta, 0.0)
	progress = clampf(1.0 - _travel_left / CELL_TRAVEL_SECONDS, 0.0, 1.0)
	if _travel_left > 0.0:
		state = "working"
		return
	_try_deliver()

# 空载:从输入端邻建取一件(类型不限,由对方挑"有货且可给"的那类)。
func _try_extract():
	var source: Building = _neighbour(-direction)
	if source == null or source.provide_to(bag, "", 1) <= 0:
		state = "idle"
		progress = 0.0
		return
	# 定下展示类型:ItemStack 靠 bag.item_type 决定画什么(取来的那类此时已定)。
	# 起表不在这里 —— 见 _on_hold_changed。
	var types: Array[String] = bag.types()
	if not types.is_empty():
		bag.item_type = types[0]

# 在途缓存件数变化时起表:不管货是本带自己取的(_try_extract),还是上游传送带推进来的,
# 只要"从空变有"就开始计时。少了这一步,被推进来的那件会因为 _travel_left 本就是 0
# 而在同一帧被直接投出去 —— 整段运输被跳过。
func _on_hold_changed():
	if bag.count > 0 and _travel_left <= 0.0:
		_travel_left = CELL_TRAVEL_SECONDS
		progress = 0.0
		state = "working"

# 到站:投给输出端邻建。投不出去(对面为空 / 收不下)就卡住,progress 停在 1,下帧重试。
func _try_deliver():
	var held_type: String = _held_type()
	var target: Building = _neighbour(direction)
	if not held_type.is_empty() and target != null and target.accept_from(bag, held_type, 1) > 0:
		bag.item_type = ""
		_travel_left = 0.0
		progress = 0.0
		state = "idle"
		return
	state = "blocked"

# 带上那件的类型:展示用 bag.item_type 已由 _try_extract 定下,这里兜底从内容反查。
func _held_type() -> String:
	if not bag.item_type.is_empty():
		return bag.item_type
	var types: Array[String] = bag.types()
	return types[0] if not types.is_empty() else ""

# 取邻建:每 tick 重新查,不缓存引用 —— Map.remove_building 会先清 cell.building 再
# queue_free,缓存下来的引用会悬空。
func _neighbour(in_offset: Vector2i) -> Building:
	if not Level.current or not Level.current.map:
		return null
	var neighbour_cell: Cell = Level.current.map.get_cell(axis + in_offset)
	if not neighbour_cell:
		return null
	return neighbour_cell.building
