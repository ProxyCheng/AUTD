class_name SpatialIndex
extends RefCounted

# 自平衡空间索引树 = 红黑树(平衡)+ 空间填充曲线(把 2D 拉成 1D)+ 子树包围盒(空间剪枝)。
# 三个想法各管一件事:
#   1. Morton 码:把 (x, y) 的位交错成一个整数键,空间上相邻的点键也大致相邻(有少量跳变),
#      于是"空间近"变成"树里近" —— 中序的一段子树 = 空间上成簇的一批点;
#   2. 红黑树:按该键维持 O(log n) 高度,插入/删除/旋转都由 RB 不变式兜住,动态增删不退化;
#   3. 子树包围盒:每个节点额外记"本子树(含自身)的 AABB",查询矩形时不相交就整棵剪掉。
#      光有 Morton 键只能做范围扫描,加上 AABB 才是"按矩形剪枝"的空间索引。
#
# 为什么旋转不必重算祖先包围盒:旋转不改变任何子树里**点的集合**(左旋后 Y 的子树 = 原来的
# {Y} ∪ X 的子树),变的只有被转的那两个节点自身,故 _rotate_* 里就地更新这两个即可;
# 而"点集变了"的传播只需沿插入/删除点那条祖先链自下而上重算 —— 旋转不改变节点的祖先集合。
#
# 复杂度:插入/删除/移动 O(log n);矩形查询 O(log n + k)(k = 命中数,常数取决于包围盒松紧)。
# 与均匀网格的分工:世界大而稀疏 / 坐标无界 / 对象大小差异大 / 增删多而查询相对少 → 本类更优;
# 世界本来就是小格子、查询都是小矩形(本项目当前情形)→ 均匀网格更省(移动多数帧是 O(1))。
# 两者对外只有 Room.get_entities_in_rect 一个入口,换实现不动调用方。

# —— 空间填充曲线(Morton 码)——
# 每轴 16 位 → 65536 格;世界坐标经 OFFSET 平移后落在 [0, 65535],越界夹住。
const AXIS_BITS: int = 16
const AXIS_MAX: int = (1 << AXIS_BITS) - 1
const AXIS_OFFSET: float = float(1 << (AXIS_BITS - 1))
# 一个世界单位 = 一格的量化步长(与游戏网格一致)
const CELL_UNITS: float = 1.0

# 红黑树节点。不叫 Node:那会遮住引擎的 Node。
class IndexNode:
	var key: int = 0
	var entity: Entity = null
	# 本子树(含自身)的包围盒 —— 查询靠它剪枝
	var box: Rect2 = Rect2()
	var red: bool = true
	var left: IndexNode = null
	var right: IndexNode = null
	var parent: IndexNode = null

var _root: IndexNode = null
# { Entity: IndexNode }:删除/更新要按实体反查节点,故另存一份
var _nodes: Dictionary = {}
var _count: int = 0

func size() -> int:
	return _count

func is_empty() -> bool:
	return _count == 0

func contains(in_entity: Entity) -> bool:
	return _nodes.has(in_entity)

# 插入实体(按当前位置定键)。已在索引里则忽略。
func insert(in_entity: Entity):
	if _nodes.has(in_entity):
		return
	var node := IndexNode.new()
	node.key = morton_key(in_entity.position)
	node.entity = in_entity
	node.box = _point_box(in_entity.position)
	var parent: IndexNode = null
	var current: IndexNode = _root
	while current:
		parent = current
		# 同键(同格)的多个实体一律往右挂,保证键相等也能共存
		current = current.right if node.key >= current.key else current.left
	node.parent = parent
	if parent == null:
		_root = node
	elif node.key >= parent.key:
		parent.right = node
	else:
		parent.left = node
	_nodes[in_entity] = node
	_count += 1
	_fix_insert(node)
	# 旋转只维护被转的那两个,故这里沿插入点重算"点集变了"的那条祖先链。
	# 从父节点起(新节点自己的包围盒建好时就是对的),而且一旦某层的并集没变就停 ——
	# 小步移动多数帧在第一层就停住,移动成本因此接近常数。
	_refresh_box_upward(node.parent)

# 删除实体。不在索引里则忽略。
func remove(in_entity: Entity):
	var node: IndexNode = _nodes.get(in_entity, null)
	if node == null:
		return
	_nodes.erase(in_entity)
	_count -= 1

	var moved: IndexNode = node          # 顶替 node 位置的那个(CLRS 的 y)
	var moved_red: bool = moved.red
	var x: IndexNode = null              # 接在 moved 原位上的那个(可能为 null)
	var x_parent: IndexNode = null
	if node.left == null:
		x = node.right
		x_parent = node.parent
		_transplant(node, node.right)
	elif node.right == null:
		x = node.left
		x_parent = node.parent
		_transplant(node, node.left)
	else:
		moved = _minimum(node.right)
		moved_red = moved.red
		x = moved.right
		if moved.parent == node:
			x_parent = moved
		else:
			x_parent = moved.parent
			_transplant(moved, moved.right)
			moved.right = node.right
			moved.right.parent = moved
		_transplant(node, moved)
		moved.left = node.left
		moved.left.parent = moved
		moved.red = node.red
	if not moved_red:
		_fix_remove(x, x_parent)
	# 结构定了再自下而上重建包围盒(被摘节点原来那条链)
	_refresh_box_upward(x_parent if x_parent else _root)

# 实体位置变了:同格只重算包围盒链(不影响树序),跨格则摘了重插。
func update(in_entity: Entity):
	var node: IndexNode = _nodes.get(in_entity, null)
	if node == null:
		return
	if morton_key(in_entity.position) == node.key:
		# 同格:只重算包围盒链(树序不变,不必摘了重插)
		_refresh_box_upward(node)
		return
	remove(in_entity)
	insert(in_entity)

# 落在 in_rect 内的实体:按子树包围盒剪枝,不相交的整棵跳过。
func query(in_rect: Rect2) -> Array:
	var found: Array = []
	_collect(_root, in_rect, found)
	return found

func _collect(in_node: IndexNode, in_rect: Rect2, r_found: Array):
	if in_node == null:
		return
	if not _rects_overlap(in_node.box, in_rect):
		return
	_collect(in_node.left, in_rect, r_found)
	if in_rect.has_point(in_node.entity.position):
		r_found.append(in_node.entity)
	_collect(in_node.right, in_rect, r_found)

# —— 键:2D → 1D(Morton 码)——

# 位置 → Morton 键。每轴先量化到 [0, 65535],再把两轴按位交错。
static func morton_key(in_position: Vector2) -> int:
	var x: int = clampi(int(floorf(in_position.x / CELL_UNITS + AXIS_OFFSET)), 0, AXIS_MAX)
	var y: int = clampi(int(floorf(in_position.y / CELL_UNITS + AXIS_OFFSET)), 0, AXIS_MAX)
	return _spread_bits(x) | (_spread_bits(y) << 1)

# 把 16 位整数按位散开到偶数位(经典 bit-interleave)
static func _spread_bits(in_value: int) -> int:
	var v: int = in_value & 0xFFFF
	v = (v | (v << 8)) & 0x00FF00FF
	v = (v | (v << 4)) & 0x0F0F0F0F
	v = (v | (v << 2)) & 0x33333333
	v = (v | (v << 1)) & 0x55555555
	return v

# —— 红黑树:旋转(顺带就地维护被转那两个的包围盒)——

func _rotate_left(in_node: IndexNode):
	var pivot: IndexNode = in_node.right
	in_node.right = pivot.left
	if pivot.left:
		pivot.left.parent = in_node
	pivot.parent = in_node.parent
	if in_node.parent == null:
		_root = pivot
	elif in_node == in_node.parent.left:
		in_node.parent.left = pivot
	else:
		in_node.parent.right = pivot
	pivot.left = in_node
	in_node.parent = pivot
	# 集合变的只有这两个:先算落到下面的 in_node,再算上提的 pivot
	in_node.box = _subtree_box(in_node)
	pivot.box = _subtree_box(pivot)

func _rotate_right(in_node: IndexNode):
	var pivot: IndexNode = in_node.left
	in_node.left = pivot.right
	if pivot.right:
		pivot.right.parent = in_node
	pivot.parent = in_node.parent
	if in_node.parent == null:
		_root = pivot
	elif in_node == in_node.parent.right:
		in_node.parent.right = pivot
	else:
		in_node.parent.left = pivot
	pivot.right = in_node
	in_node.parent = pivot
	in_node.box = _subtree_box(in_node)
	pivot.box = _subtree_box(pivot)

# —— 红黑树:插入修复(CLRS)——

func _fix_insert(in_node: IndexNode):
	var node: IndexNode = in_node
	while node.parent and node.parent.red:
		var grand: IndexNode = node.parent.parent
		if node.parent == grand.left:
			var uncle: IndexNode = grand.right
			if uncle and uncle.red:
				node.parent.red = false
				uncle.red = false
				grand.red = true
				node = grand
			else:
				if node == node.parent.right:
					node = node.parent
					_rotate_left(node)
				node.parent.red = false
				node.parent.parent.red = true
				_rotate_right(node.parent.parent)
		else:
			var uncle: IndexNode = grand.left
			if uncle and uncle.red:
				node.parent.red = false
				uncle.red = false
				grand.red = true
				node = grand
			else:
				if node == node.parent.left:
					node = node.parent
					_rotate_right(node)
				node.parent.red = false
				node.parent.parent.red = true
				_rotate_left(node.parent.parent)
	_root.red = false

# —— 红黑树:删除修复(CLRS,用显式父指针代替 nil 哨兵)——

func _fix_remove(in_node: IndexNode, in_parent: IndexNode):
	var node: IndexNode = in_node
	var parent: IndexNode = in_parent
	while node != _root and (node == null or not node.red):
		if node == parent.left:
			var sibling: IndexNode = parent.right
			if sibling and sibling.red:
				sibling.red = false
				parent.red = true
				_rotate_left(parent)
				sibling = parent.right
			if sibling == null:
				node = parent
				parent = node.parent
				continue
			if (sibling.left == null or not sibling.left.red) \
					and (sibling.right == null or not sibling.right.red):
				sibling.red = true
				node = parent
				parent = node.parent
			else:
				if sibling.right == null or not sibling.right.red:
					if sibling.left:
						sibling.left.red = false
					sibling.red = true
					_rotate_right(sibling)
					sibling = parent.right
				sibling.red = parent.red
				parent.red = false
				if sibling.right:
					sibling.right.red = false
				_rotate_left(parent)
				node = _root
				parent = null
		else:
			var sibling: IndexNode = parent.left
			if sibling and sibling.red:
				sibling.red = false
				parent.red = true
				_rotate_right(parent)
				sibling = parent.left
			if sibling == null:
				node = parent
				parent = node.parent
				continue
			if (sibling.right == null or not sibling.right.red) \
					and (sibling.left == null or not sibling.left.red):
				sibling.red = true
				node = parent
				parent = node.parent
			else:
				if sibling.left == null or not sibling.left.red:
					if sibling.right:
						sibling.right.red = false
					sibling.red = true
					_rotate_left(sibling)
					sibling = parent.left
				sibling.red = parent.red
				parent.red = false
				if sibling.left:
					sibling.left.red = false
				_rotate_right(parent)
				node = _root
				parent = null
	if node:
		node.red = false

func _transplant(in_old: IndexNode, in_new: IndexNode):
	if in_old.parent == null:
		_root = in_new
	elif in_old == in_old.parent.left:
		in_old.parent.left = in_new
	else:
		in_old.parent.right = in_new
	if in_new:
		in_new.parent = in_old.parent

func _minimum(in_node: IndexNode) -> IndexNode:
	var node: IndexNode = in_node
	while node.left:
		node = node.left
	return node

# —— 子树包围盒 ——

# 自下而上重算包围盒。不做"没变就早停"的优化:试过,在不变量测试里被证伪 ——
# 单个实体的包围盒是零尺寸矩形,Rect2.merge 对零面积矩形的处理会让"某层没变"推不出
# "上面都没变"。正确性优先,插入/删除/移动一律走到根(实测一次移动约 130µs,见提交说明)。
func _refresh_box_upward(in_node: IndexNode):
	var node: IndexNode = in_node
	while node:
		node.box = _subtree_box(node)
		node = node.parent

func _subtree_box(in_node: IndexNode) -> Rect2:
	var box: Rect2 = _point_box(in_node.entity.position)
	if in_node.left:
		box = box.merge(in_node.left.box)
	if in_node.right:
		box = box.merge(in_node.right.box)
	return box

func _point_box(in_position: Vector2) -> Rect2:
	return Rect2(in_position, Vector2.ZERO)

# 零尺寸矩形也算相交:单个实体的包围盒就是一个点,用 Rect2.intersects 会判成不相交。
static func _rects_overlap(in_a: Rect2, in_b: Rect2) -> bool:
	return in_a.position.x <= in_b.end.x and in_b.position.x <= in_a.end.x \
			and in_a.position.y <= in_b.end.y and in_b.position.y <= in_a.end.y
