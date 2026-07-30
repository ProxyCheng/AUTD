class_name Room

class RoomRegion:
	var range: Rect2i = Rect2i(0, 0, 0, 0)
	var children: Array = []
	
	func add_entity(in_entity: Entity):
		children.append(in_entity)
	
	func remove_entity(in_entity: Entity):
		var index = children.find(in_entity)
		children.remove_at(index)
	
	func tick(in_delta: float):
		for child in children:
			child.tick(in_delta)

var region: RoomRegion = RoomRegion.new()
var entities: Dictionary = {}

signal entities_changed(added_entity_ids: Array, removed_entity_ids: Array)

func add_entity(in_entity: Entity):
	region.add_entity(in_entity)
	entities.set(in_entity.id, in_entity)
	entities_changed.emit([in_entity.id], [])

func remove_entity(in_entity_id: int):
	var entity: Entity = entities.get(in_entity_id)
	if not entity:
		return
	region.remove_entity(entity)
	entities.erase(in_entity_id)
	entities_changed.emit([], [in_entity_id])

func get_entity(in_entity_id: int):
	return entities.get(in_entity_id)

func tick(in_delta: float):
	region.tick(in_delta)
