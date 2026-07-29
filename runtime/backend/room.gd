class_name Room

class RoomRegion:
	var range: Rect2i = Rect2i(0, 0, 0, 0)
	var children: Array = []
	
	func add_entity(in_entity: Entity):
		children.append(in_entity)
	
	func tick(in_delta: float):
		for child in children:
			child.tick(in_delta)

var region: RoomRegion = RoomRegion.new()
var entities: Dictionary = {}

signal entities_added(entity_ids: Array)

func add_entity(in_entity: Entity):
	region.add_entity(in_entity)
	entities.set(in_entity.id, in_entity)
	entities_added.emit([in_entity.id])

func get_entity(in_entity_id: int):
	return entities.get(in_entity_id)

func tick(in_delta: float):
	region.tick(in_delta)
