extends Node
class_name Room

# 实体空间索引:按 CELL_SIZE 的方格分桶,把"某矩形内有哪些实体"从 O(全部实体) 降到
# O(覆盖到的格子数 + 桶内实体数)。用均匀网格而不是四叉树,理由:
#   * 本作世界本来就是 1×1 的格子(y=0 平面),实体位置也按格取整,网格是它的自然结构;
#   * 查询都是小矩形(炮塔射程 3 格、炮弹落点半径),网格桶查找是常数,没有树遍历开销;
#   * 实体每 tick 都在动,四叉树要频繁摘/插节点并可能分裂合并,网格多数帧"格子没变就什么都不做"。
# 将来若世界变得又大又稀疏(实体只聚集在少数区域),把 entities_in_rect 换成四叉树即可 ——
# 对外只有 Room.get_entities_in_rect 一个入口,调用方不用动。
class RoomRegion:
	const CELL_SIZE: float = 4.0

	# 实体列表:保持插入序 —— 实体 tick 顺序由它决定。
	var children: Array = []
	# { Vector2i: Array[Entity] }
	var _buckets: Dictionary = {}
	# { Entity: Vector2i } 实体当前所在桶
	var _cells: Dictionary = {}

	func add_entity(in_entity: Entity):
		children.append(in_entity)
		var cell: Vector2i = _cell_of(in_entity.position)
		_cells[in_entity] = cell
		_bucket_for(cell).append(in_entity)
		# 换桶挂在实体自己的 position_changed 上,而不是在 tick 里比对前后位置:实体可能在 tick
		# 之外被直接挪动(炮弹生成时先摆好位置再入房),那样比对会漏,查询就会指到旧格。
		if not in_entity.position_changed.is_connected(_on_entity_position_changed):
			in_entity.position_changed.connect(_on_entity_position_changed.bind(in_entity))

	func remove_entity(in_entity: Entity):
		var index: int = children.find(in_entity)
		if index < 0:
			return
		children.remove_at(index)
		var cell: Vector2i = _cells.get(in_entity, _cell_of(in_entity.position))
		_cells.erase(in_entity)
		var bucket: Array = _buckets.get(cell, [])
		var at: int = bucket.find(in_entity)
		if at >= 0:
			bucket.remove_at(at)

	func tick(in_delta: float):
		for child: Entity in children:
			child.tick(in_delta)

	# 落在 in_rect 内的实体:只遍历覆盖到的格子,结果与逐个比对全场实体一致。
	func entities_in_rect(in_rect: Rect2) -> Array:
		var found: Array = []
		var from: Vector2i = _cell_of(in_rect.position)
		var to: Vector2i = _cell_of(in_rect.end)
		for cy: int in range(from.y, to.y + 1):
			for cx: int in range(from.x, to.x + 1):
				for entity: Entity in _buckets.get(Vector2i(cx, cy), []):
					if in_rect.has_point(entity.position):
						found.append(entity)
		return found

	# 位置 → 桶坐标(向下取整,负坐标也正确)
	func _cell_of(in_position: Vector2) -> Vector2i:
		return Vector2i(floori(in_position.x / CELL_SIZE), floori(in_position.y / CELL_SIZE))

	func _bucket_for(in_cell: Vector2i) -> Array:
		return _buckets.get_or_add(in_cell, [])

	# 实体位置变化 → 跨格才换桶(同格什么都不做,这是网格相对四叉树的好处)。
	# 实体已不在索引里(自己 tick 里自毁后又被挪动)时直接返回,别把它重新挂回去。
	func _on_entity_position_changed(in_entity: Entity):
		if not _cells.has(in_entity):
			return
		var old_cell: Vector2i = _cells[in_entity]
		var new_cell: Vector2i = _cell_of(in_entity.position)
		if new_cell == old_cell:
			return
		var old_bucket: Array = _buckets.get(old_cell, [])
		var at: int = old_bucket.find(in_entity)
		if at >= 0:
			old_bucket.remove_at(at)
		_cells[in_entity] = new_cell
		_bucket_for(new_cell).append(in_entity)

var region: RoomRegion = RoomRegion.new()
var entities: Dictionary = {}

signal entities_changed(added_entity_ids: Array, removed_entity_ids: Array)

func add_entity(in_entity: Entity):
	region.add_entity(in_entity)
	entities.set(in_entity.id, in_entity)
	add_child(in_entity)
	in_entity.owner = owner
	entities_changed.emit([in_entity.id], [])

func remove_entity(in_entity_id: int):
	var entity: Entity = entities.get(in_entity_id)
	if not entity:
		return
	region.remove_entity(entity)
	entities.erase(in_entity_id)
	remove_child(entity)
	entity.queue_free()
	entities_changed.emit([], [in_entity_id])

func get_entity(in_entity_id: int):
	return entities.get(in_entity_id)

func tick(in_delta: float):
	region.tick(in_delta)

func get_entities_in_rect(in_rect: Rect2) -> Array:
	return region.entities_in_rect(in_rect)
