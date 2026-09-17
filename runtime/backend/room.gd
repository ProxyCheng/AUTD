extends Node
class_name Room

# 实体空间索引:交给 SpatialIndex(红黑树 × Morton 键 × 子树包围盒,自平衡)。
# 本类只管两件与房间相关的事:
#   1. 实体 tick 顺序 —— children 保持插入序(索引树是中序,不能拿它当 tick 顺序);
#   2. 与实体的接线 —— 位置一变就更新索引(见 _on_entity_position_changed)。
# 对外查询仍是 Room.get_entities_in_rect,换索引实现不用动调用方。
class RoomRegion:
	# 实体列表:保持插入序 —— 实体 tick 顺序由它决定。
	var children: Array = []
	# 自平衡空间索引(见 SpatialIndex)
	var index: SpatialIndex = SpatialIndex.new()

	func add_entity(in_entity: Entity):
		children.append(in_entity)
		index.insert(in_entity)
		# 索引更新挂在实体自己的 position_changed 上,而不是在 tick 里比对前后位置:实体可能在 tick
		# 之外被直接挪动(炮弹生成时先摆好位置再入房),那样比对会漏,查询就会指到旧位置。
		if not in_entity.position_changed.is_connected(_on_entity_position_changed):
			in_entity.position_changed.connect(_on_entity_position_changed.bind(in_entity))

	func remove_entity(in_entity: Entity):
		var index_of_entity: int = children.find(in_entity)
		if index_of_entity < 0:
			return
		children.remove_at(index_of_entity)
		index.remove(in_entity)

	func tick(in_delta: float):
		for child: Entity in children:
			child.tick(in_delta)

	# 落在 in_rect 内的实体:按子树包围盒剪枝(见 SpatialIndex.query),结果与逐个比对全场一致。
	func entities_in_rect(in_rect: Rect2) -> Array:
		return index.query(in_rect)

	func _on_entity_position_changed(in_entity: Entity):
		index.update(in_entity)

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
