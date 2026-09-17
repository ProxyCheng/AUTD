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
# 当前选中的 backend 对象(LevelActor.selected_target 的镜像):实体重新进入可视区时
# 用它恢复选中环(见 _place_entity_actor)。
var _selected_target: Object = null

func _ready():
	# 监听 LevelActor 的选中切换(与 map_actor 同款接线:父节点已带脚本,可先于其 _ready 连接)。
	var la := get_parent() as LevelActor
	if la and not la.selected_changed.is_connected(_on_selected_changed):
		la.selected_changed.connect(_on_selected_changed)

func bind(in_room: Room, in_logistics: Logistics):
	room = in_room
	room.entities_changed.connect(_on_entities_changed)
	# 相机可见格变化 → 补判一次实体可见性。实体的显隐目前只在它自己 position_changed 时结算,
	# 而静止不动的实体(走出视野后停下的工人、在视野外生成后一直没动的实体)等不到那次信号,
	# 相机再移回来也永远不显示。建筑/地表由 map_actor 在同一信号里结算(§5.5 可见性策略)。
	var camera: CameraController = get_viewport().get_camera_3d() as CameraController
	if camera and not camera.viewing_axis_changed.is_connected(_on_viewing_axis_changed):
		camera.viewing_axis_changed.connect(_on_viewing_axis_changed)
	# 计时搬运开始 → 由本节点转给对应工人 actor 播飞行(见 _on_transfer_started)。
	# 只连一次:bind 在组合根里只调一次,判重是防测试/重载场景重复接线。
	if in_logistics and not in_logistics.transfer_started.is_connected(_on_transfer_started):
		in_logistics.transfer_started.connect(_on_transfer_started)

# 相机可见格变化:逐实体按当前可见性同步 actor。相机只在可见格集合真的变化时才发这个信号
# (见 CameraController._update_viewing_axis),故不是每帧全扫。
func _on_viewing_axis_changed(_in_new_axis: Dictionary, _in_old_axis: Dictionary):
	var camera: CameraController = get_viewport().get_camera_3d() as CameraController
	if not camera or not room:
		return
	for entity_id in room.entities:
		var entity: Entity = room.get_entity(entity_id)
		if entity:
			_sync_entity_actor(entity, camera.is_position_visible(entity.position))

# 选中变化:缓存目标,并让全部在场 actor 重新判定高亮 —— 单一 selected_target 保证
# 任意时刻至多一个高亮(选中工人时建筑环全灭,反之亦然)。
func _on_selected_changed(in_target: Object):
	_selected_target = in_target
	for entity_actor: EntityActor in entity_actors.values():
		entity_actor.set_selected(entity_actor.entity == in_target)

# 点击拾取的候选实体 actor:在场、可见、且 backend 对象为 Creature 的实体。
# 遍历 entity_actors(而非 backend entities):该表只存已放置 actor,回收时先 erase,
# 故每条记录都有有效 entity,天然只拾取可见者。
# Creature 即检视范围:炮弹/箭矢 extends Ballistic(非 Creature),不参与命中、不吞点击。
func pick_candidates() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for entity_actor: EntityActor in entity_actors.values():
		if not entity_actor.visible or not entity_actor.entity:
			continue
		if entity_actor.entity is not Creature:
			continue
		candidates.append(entity_actor)
	return candidates

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
		_sync_entity_actor(entity, camera.is_position_visible(entity.position))

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

# 一次计时搬运开始 → 挂上它的"逐件起飞"事件(见 _on_item_departed)。
# 这里**不**立刻起飞行:后端是逐件取、逐件交(见 ItemTransfer._advance),飞行也该逐件起 ——
# 开场就按件数摆 N 段会飞出并不存在的货(源仓可能被并发搬空而少给)。
func _on_transfer_started(in_transfer: ItemTransfer):
	if not _labor_of(in_transfer):
		return
	if not in_transfer.item_departed.is_connected(_on_item_departed):
		in_transfer.item_departed.connect(_on_item_departed.bind(in_transfer))

# 某一件刚离开源仓 → 让对应工人 actor 起这一段飞行。
# 每次都重新按 labor.id 找 actor:一批要飞好几段,中途工人可能已走出可视区被回收(那就不播)。
func _on_item_departed(in_index: int, in_transfer: ItemTransfer):
	var labor: Labor = _labor_of(in_transfer)
	if not labor:
		return
	var actor: EntityActor = entity_actors.get(labor.id)
	if not actor:
		return
	actor.spawn_transfer_flight(in_transfer, in_index, self)

# 这次搬运涉及的工人:哪一端的仓挂在 Labor 下,那一端就是(两端都不是 → null)。
func _labor_of(in_transfer: ItemTransfer) -> Labor:
	var from_source: Labor = _labor_of_bag(in_transfer.source_bag)
	if from_source:
		return from_source
	return _labor_of_bag(in_transfer.dest_bag)

# 该仓所属的工人;仓挂在建筑下(或已销毁)→ null。先 is_instance_valid 再用,别碰 freed 实例。
func _labor_of_bag(in_bag: Bag) -> Labor:
	if not is_instance_valid(in_bag):
		return null
	return in_bag.get_parent() as Labor

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
	# 恢复缓存选中:选中的工人走出可视区被回收、再次进入视野时,环要跟着回来。
	entity_actor.set_selected(entity_actor.entity == _selected_target)
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
	var camera: CameraController = get_viewport().get_camera_3d() as CameraController
	if not camera:
		return
	_sync_entity_actor(entity, camera.is_position_visible(entity.position))

# 按可见性放置/回收实体 actor —— 显隐结算的唯一实现:
# 实体自己移动(_on_entity_position_changed)与相机移动(_on_viewing_axis_changed)共用它。
func _sync_entity_actor(in_entity: Entity, in_visible: bool):
	if in_visible:
		if not entity_actors.has(in_entity.id):
			_place_entity_actor(in_entity.id)
	elif entity_actors.has(in_entity.id):
		_recycle_entity_actor(in_entity.id)
