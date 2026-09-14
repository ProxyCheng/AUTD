extends Node
class_name RoomActor

# 实体消失表现(按类型):炮弹命中即爆炸,在落点补一次区域爆裂(粒子 + 音效)。
# 由已有的 entities_changed 移除事件驱动,不为此在 backend 增信号(§5.7)。
const REMOVAL_FX_BY_TYPE: Dictionary = {
	&"cannonball": preload("res://runtime/frontend/models/entities/cannonball/cannonball_burst.tscn"),
}
# 消失音效(按类型):世界空间定位音,由 AudioManager 按到摄像机距离衰减(近大远小)。
const REMOVAL_SFX_BY_TYPE: Dictionary = {
	&"cannonball": &"cannonball_explode",
}

var room: Room = null
var entity_actors: Dictionary = {}
var entity_actors_pool: Dictionary = {}

func bind(in_room: Room):
	room = in_room
	room.entities_changed.connect(_on_entities_changed)

func _on_entities_changed(in_added_entity_ids: Array, in_removed_entity_ids: Array):
	var camera: CameraController = get_viewport().get_camera_3d()
	for entity_id in in_removed_entity_ids:
		# 先于回收:此时 actor 仍持有落点位置
		_play_removal_fx(entity_id)
		_recycle_entity_actor(entity_id)
	for entity_id in in_added_entity_ids:
		var entity: Entity = room.get_entity(entity_id)
		if not entity:
			continue
		entity.position_changed.connect(_on_entity_position_changed.bind(entity.id))
		if camera.is_position_visible(entity.position):
			_place_entity_actor(entity_id)

# 实体被移除时,在 actor 最后的世界位置播一次消失表现(爆裂粒子 + 定位音)。
# 仅当该类型登记了表现、且 actor 仍在场时(炮弹在屏幕外被回收则无需表现)。
func _play_removal_fx(in_entity_id: int):
	var entity_actor: EntityActor = entity_actors.get(in_entity_id)
	if not entity_actor:
		return
	var type: StringName = StringName(entity_actor.type)
	var position: Vector3 = entity_actor.global_position
	var fx_scene: PackedScene = REMOVAL_FX_BY_TYPE.get(type, null)
	if fx_scene:
		var fx: Node3D = fx_scene.instantiate()
		add_child(fx)
		fx.global_position = position
	var sfx_id: StringName = REMOVAL_SFX_BY_TYPE.get(type, &"")
	if sfx_id != &"":
		AudioManager.sfx_at(sfx_id, position, randf_range(0.95, 1.05))

func _place_entity_actor(in_entity_id: int):
	var entity: Entity = room.get_entity(in_entity_id)
	if not entity:
		return
	var type_key: String = entity.get_type_key()
	var entity_actors_of_type_key: Array = entity_actors_pool.get(type_key, [])
	var entity_actor: EntityActor = null
	if entity_actors_of_type_key:
		entity_actor = entity_actors_of_type_key.pop_back()
	else:
		var entity_scene: PackedScene = preload("res://runtime/frontend/actors/entity_actor.tscn")
		entity_actor = entity_scene.instantiate()
		add_child(entity_actor)
		entity_actor.owner = owner
	entity_actor.bind(entity)
	entity_actor.show()
	entity_actors.set(in_entity_id, entity_actor)

func _recycle_entity_actor(in_entity_id: int):
	var entity_actor: EntityActor = entity_actors.get(in_entity_id)
	if not entity_actor:
		return
	var type_key: String = entity_actor.get_type_key()
	entity_actor.bind(null)
	entity_actor.hide()
	entity_actors.erase(in_entity_id)
	entity_actors_pool.get_or_add(type_key, []).append(entity_actor)

func _on_entity_position_changed(in_entity_id: int):
	var entity: Entity = room.get_entity(in_entity_id)
	if not entity:
		return
	var camera: CameraController = get_viewport().get_camera_3d()
	if camera and camera.is_position_visible(entity.position):
		if not entity_actors.has(in_entity_id):
			_place_entity_actor(in_entity_id)
	else:
		if entity_actors.has(in_entity_id):
			_recycle_entity_actor(in_entity_id)
