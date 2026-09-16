class_name Bag
extends Node

# 物品仓库(挂在建筑/实体下,由 Logistics 统一调度搬运)。
#
# 内容:Array[BagItem] —— 每格是"同类型的若干件":
#   * 散料(原木/石头/箭/炮弹…):只记 item_type + count,同类型**恒合并成一格**;
#   * 有状态物品(工具耐久、未来的保鲜度…):count 恒 1、state 指向该件的载体,**每件各占一格**。
#
# 单类型 vs 多类型:仓**结构上支持**装多种物品(按类型各占一格),但绝大多数仓只用一种类型
# (item_type 声明,Logistics 按它做单类型供需撮合)。多类型目前只用在**工人随身仓**上 ——
# 它不注册 Logistics,故供需撮合不受影响;此时 item_type 表示"主要类型",按类型读写走
# *_of 系列,展示侧用 ItemStack.bind(bag, type) 绑到指定类型。
#
# 三层数量语义(count 为整仓件数,各类型求和):
#   max_count            严格物理上限,count 永不超过它(add_count 按剩余空间截断)。
#   preferred_min_count  舒适下限:count < 该值 → 本 bag 处于"缺货请求"态,希望被补货。
#   preferred_max_count  舒适上限:count > 该值 → 本 bag 处于"富余供给"态,超出部分可外供;
#                        count 达到它即视为"补货完成",不再触发搬运请求。
#   [preferred_min, preferred_max] 之间为舒适区,不参与搬运。
# 纯请求方(bag 自己只进不出):preferred_min = preferred_max = max_count。
# 纯供给方(bag 自己只出不进):preferred_min = preferred_max = 0(有货即外供)。
# 仓储型:preferred_min 为自留警戒线(低于它求补),preferred_max 为外供起点(高于它才出)。
# 注意 preferred_max_count 应 <= max_count。

static var next_id: int = 1
var id: int = 0

# 物品类型(可观察:变化时广播 item_type_changed,供 frontend ItemStack 跟随)。
# 单类型仓 = 本仓唯一类型;多类型仓 = "主要类型"(按类型读写请用 *_of 系列)。
var item_type: String = "":
	get:
		return item_type
	set(in_type):
		if in_type == item_type:
			return
		item_type = in_type
		item_type_changed.emit()

# 可选的"状态载体工厂":入库时以 item_type 调用,返回该件的状态载体(如工具实例)。
# 不设时走 default_state_factory(按类型探 backend 实体类),故任意仓都能自动保住
# 工具的按件状态(如接收工人归还工具的 Stockpile),无需逐仓配置。
var state_factory: Callable = Callable()

# 仓内各格(散料按类型各合并成一格;有状态物品每件一格)
var items: Array[BagItem] = []

var max_count: int = 10
var preferred_min_count: int = 0
var preferred_max_count: int = max_count
# 整仓件数(各格求和,只读;写入一律经 add_count/remove_count)。
var count: int:
	get:
		var total: int = 0
		for entry: BagItem in items:
			total += entry.count
		return total

# 所属建筑中心(由建筑在创建 bag 后设置,= Vector2(axis)):
# Logistics 匹配按此度量距离;搬运移动以其为直线接近目标,由 transport_haul 的
# MoveToTargetTask.arrival_center_offset 决定"停在距建筑中心固定偏移"的停靠圈。
var access_position: Vector2 = Vector2.ZERO
# 补货(搬运)任务的调度优先级:由创建该 bag 的建筑按需求紧急度声明。
# 默认普通搬运 0;Crossbow 弹药箱这类攻击建筑设为更高(供弹优先于普通物流)。
var transport_priority: int = 0

signal count_changed()
signal item_type_changed()

func _init():
	id = next_id
	next_id += 1

# —— 按类型的读写(多类型仓用;单类型仓等价于不带 _of 的版本)——

# 仓内全部类型(保持建格顺序)。
func types() -> Array[String]:
	var out: Array[String] = []
	for entry: BagItem in items:
		if entry.item_type not in out:
			out.append(entry.item_type)
	return out

# 某类型的件数(单类型仓即整仓 count)。
func count_of(in_item_type: String) -> int:
	var total: int = 0
	for entry: BagItem in items:
		if entry.item_type == in_item_type:
			total += entry.count
	return total

# 入库:按剩余空间接受 in_amount 件,返回实际入库数(超出 max_count 部分丢弃)。
# 该类型若有状态载体则逐件造载体、每件各占一格,否则合并进同类型的散料格。
func add_count_of(in_item_type: String, in_amount: int) -> int:
	if in_item_type.is_empty() or in_amount <= 0:
		return 0
	var accepted: int = mini(in_amount, max_count - count)
	if accepted <= 0:
		return 0
	var stored: int = _store(in_item_type, accepted)
	if stored <= 0:
		return 0
	count_changed.emit()
	return stored

# 出库:吐出 in_amount 件,返回实际出库数(不足部分少给)。
# 有状态格:整格取出并释放其载体(丢弃语义;要保留实例请用 peek_state 后自行接管)。
# in_item_type 为空 = 不限类型(整仓任意格,供兜底清仓用)。
func remove_count_of(in_item_type: String, in_amount: int) -> int:
	if in_amount <= 0:
		return 0
	var any_type: bool = in_item_type.is_empty()
	var removed: int = 0
	var want: int = in_amount
	for i in range(items.size() - 1, -1, -1):
		if want <= 0:
			break
		var entry: BagItem = items[i]
		if not any_type and entry.item_type != in_item_type:
			continue
		var take: int = mini(entry.count, want)
		if take <= 0:
			continue
		entry.count -= take
		removed += take
		want -= take
		if entry.count <= 0:
			_drop_entry(i)
	if removed > 0:
		count_changed.emit()
	return removed

# 入库/出库的简写:按本仓 item_type 操作(单类型仓的常用路径)。
func add_count(in_amount: int) -> int:
	return add_count_of(item_type, in_amount)

func remove_count(in_amount: int) -> int:
	return remove_count_of(item_type, in_amount)

# 只清"散料格"(可堆叠的搬运物),保留有状态单体(工具等),返回清掉的件数。
# 供任务结束兜底清仓:不这么分就会把工人手上的工具一起销毁。
func clear_fungible() -> int:
	var removed: int = 0
	for i in range(items.size() - 1, -1, -1):
		var entry: BagItem = items[i]
		if entry.has_state():
			continue
		removed += entry.count
		_drop_entry(i)
	if removed > 0:
		count_changed.emit()
	return removed

# 只读:第一件带状态物品的载体(如工人随身仓里那把工具);in_item_type 非空时只认该类型。
# 不取出、不改动仓,调用方只读其状态(如工具耐久)。
func peek_state(in_item_type: String = "") -> Object:
	for entry: BagItem in items:
		if not entry.has_state():
			continue
		if not in_item_type.is_empty() and entry.item_type != in_item_type:
			continue
		return entry.state
	return null

# 默认"状态载体工厂":按类型名探 backend 实体类(§5.2 的注册表约定),是工具则实例化一件。
# 未登记实体类的类型(原木/石头等散料)返回 null → 按散料入格。
# 静态:故任意仓都能自动保住工具的按件状态,不必逐仓配 state_factory。
static func default_state_factory(in_item_type: String) -> Object:
	var path: String = "res://runtime/backend/entities/%s.gd" % in_item_type
	if not ResourceLoader.exists(path):
		return null
	var carrier: Object = load(path).new()
	if carrier is Tool:
		# type 是工具的注册表主键(§5.2):Entity.create 会写,这里直接 new 也得补上,
		# 否则展示侧绑到空类型、配方的 required_tool 匹配也会失败。
		var tool: Tool = carrier
		tool.type = in_item_type
		return tool
	var node := carrier as Node
	if node:
		node.free()
	return null

# 取出一件有状态单体(**不释放载体**,交给调用方接管):摘格并返回载体;无则 null。
# 与 remove_count_of 的区别:后者是"丢弃语义"(摘格并释放载体),本方法保留实例,
# 供"把工具从随身仓挪到 Stockpile"这类搬运 —— 载体带着耐久一起走,不重置。
func take_state(in_item_type: String = "") -> Object:
	for i in range(items.size()):
		var entry: BagItem = items[i]
		if not entry.has_state():
			continue
		if not in_item_type.is_empty() and entry.item_type != in_item_type:
			continue
		items.remove_at(i)
		count_changed.emit()
		return entry.state
	return null

# 放入一件"已有载体"的有状态单体(不造新的,直接接管该实例):满仓则拒绝。
func add_state(in_item_type: String, in_carrier: Object) -> bool:
	if in_carrier == null or in_item_type.is_empty() or is_full():
		return false
	_append_stateful(in_item_type, in_carrier)
	count_changed.emit()
	return true

# 该类型是否"按件保存状态"(有状态载体工厂能造出载体,如工具)。
# 结果缓存,避免每次探测都实例化一个载体。
static var _stateful_cache: Dictionary = {}  # { item_type: bool }

static func is_stateful(in_item_type: String) -> bool:
	if _stateful_cache.has(in_item_type):
		return _stateful_cache[in_item_type]
	var carrier: Object = default_state_factory(in_item_type)
	var result: bool = carrier != null
	var node := carrier as Node
	if node:
		node.free()
	_stateful_cache.set(in_item_type, result)
	return result

func is_understocked() -> bool:
	return count < preferred_min_count

func is_overstocked() -> bool:
	return count > preferred_max_count

func is_full() -> bool:
	return count >= max_count

# —— 内部 ——

# 存入 in_amount 件 in_item_type:有状态类型逐件造载体,散料合并进同类型的那一格。
func _store(in_item_type: String, in_amount: int) -> int:
	var carrier: Object = _make_carrier(in_item_type)
	if carrier != null:
		_append_stateful(in_item_type, carrier)
		var stored: int = 1
		while stored < in_amount:
			var next_carrier: Object = _make_carrier(in_item_type)
			if next_carrier == null:
				break
			_append_stateful(in_item_type, next_carrier)
			stored += 1
		return stored
	for entry: BagItem in items:
		if entry.item_type == in_item_type and not entry.has_state():
			entry.count += in_amount
			return in_amount
	items.append(BagItem.make_fungible(in_item_type, in_amount))
	return in_amount

# 造一件状态载体:本仓的 state_factory 优先,否则退回按类型探实体类的默认工厂。
func _make_carrier(in_item_type: String) -> Object:
	if state_factory.is_valid():
		return state_factory.call(in_item_type)
	return default_state_factory(in_item_type)

func _append_stateful(in_item_type: String, in_carrier: Object):
	if in_carrier is Node:
		var node: Node = in_carrier
		# 载体可能还挂在来源仓下(见 take_state/add_state 的搬运路径),先摘再挂
		if node.get_parent():
			node.get_parent().remove_child(node)
		add_child(node)
	items.append(BagItem.make_stateful(in_item_type, in_carrier))

# 摘掉第 in_index 格;该格带状态载体(是节点)时一并释放 —— 出库即丢弃该件。
func _drop_entry(in_index: int):
	var entry: BagItem = items[in_index]
	items.remove_at(in_index)
	var carrier: Object = entry.state
	# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
	if not is_instance_valid(carrier) or not (carrier is Node):
		return
	var node: Node = carrier
	if node.get_parent() == self:
		remove_child(node)
	node.queue_free()
