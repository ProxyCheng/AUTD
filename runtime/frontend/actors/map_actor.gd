extends Node

var map: Map = null
var land_actors: Dictionary = {}
var land_actors_pool: Dictionary = {}
var building_actors: Dictionary = {}
var building_actors_pool: Dictionary = {}

func bind(in_map: Map):
	map = in_map
	map.cells_changed.connect(_on_cells_changed)

# 选中变化 → 遍历当前全部建筑 actor,仅与选中 building 相同的 actor 高亮。
# 选中目标已泛化为 Object(可为工人等 Entity):cast 成 Building 失败时为 null,
# 全部去环(单一 selected_target 保证不会出现建筑环与实体环并存)。
func _on_selected_changed(in_target: Object):
	var building: Building = in_target as Building
	for axis in building_actors.keys():
		var actor: BuildingActor = building_actors.get(axis)
		var is_selected: bool = building != null and axis == building.axis
		actor.set_selected(is_selected)

func _ready():
	var camera = get_viewport().get_camera_3d() as CameraController
	camera.viewing_axis_changed.connect(_on_viewing_axis_changed)
	# 监听 LevelActor 的选中切换,驱动建筑 actor 高亮
	var la := get_parent() as LevelActor
	if la:
		la.selected_changed.connect(_on_selected_changed)

func _on_viewing_axis_changed(in_new_axis: Dictionary, in_old_axis: Dictionary):
	for axis in in_old_axis.keys():
		_recycle_land_actor(axis)
		_recycle_building_actor(axis)
	for axis in in_new_axis.keys():
		_place_land_actor(axis)
		_place_building_actor(axis)

func _on_cells_changed(in_axis: Dictionary):
	var camera = get_viewport().get_camera_3d() as CameraController
	for axis in in_axis.keys():
		# 建筑可能被删除(cell.building → null + queue_free):无论该轴当前是否可见都要先
		# 回收其 building actor,否则 orphaned actor 在树上 _process 会访问已释放的 building
		# (freed instance)。land actor 常驻(依赖可见性),仍按可见性回收/放置。
		_recycle_building_actor(axis)
		if not camera or not camera.is_axis_visible(axis):
			continue
		_recycle_land_actor(axis)
		_place_land_actor(axis)
		_place_building_actor(axis)

func _recycle_actor(in_axis: Vector2i, ref_actors: Dictionary, ref_actors_pool: Dictionary):
	var actor = ref_actors.get(in_axis)
	if not actor:
		return
	var type_key: String = actor.get_type_key()
	actor.hide()
	# 建筑被删除后 building 会 queue_free;回收时先解绑(bind(null)),断开全部信号并清空
	# building 引用,避免 actor 在树上 _process 仍访问已释放的 building(freed instance)。
	# land/room 常驻不删,无需解绑;仅 BuildingActor 有 freed 风险。
	if actor is BuildingActor and actor.has_method(&"bind"):
		actor.call(&"bind", null)
	ref_actors.erase(in_axis)
	ref_actors_pool.get_or_add(type_key, []).append(actor)

func _place_actor(in_axis: Vector2i, in_entity, in_actor_scene: PackedScene, ref_actors: Dictionary, ref_actors_pool: Dictionary):
	if not in_entity:
		return
	var type_key = in_entity.get_type_key()
	var actors_of_type_key: Array = ref_actors_pool.get(type_key, [])
	var actor = null
	if actors_of_type_key:
		actor = actors_of_type_key.pop_back()
	else:
		actor = in_actor_scene.instantiate()
		add_child(actor)
		actor.owner = owner
	actor.bind(in_entity)
	actor.show()
	ref_actors.set(in_axis, actor)

func _recycle_land_actor(in_axis: Vector2i):
	return _recycle_actor(in_axis, land_actors, land_actors_pool)

func _place_land_actor(in_axis: Vector2i):
	var cell = map.get_cell(in_axis)
	if not cell:
		return
	var land: Land = cell.get_land()
	var land_actor_scene: PackedScene = preload("res://runtime/frontend/actors/land_actor.tscn")
	return _place_actor(in_axis, land, land_actor_scene, land_actors, land_actors_pool)

func _recycle_building_actor(in_axis: Vector2i):
	return _recycle_actor(in_axis, building_actors, building_actors_pool)

func _place_building_actor(in_axis: Vector2i):
	var cell = map.get_cell(in_axis)
	if not cell:
		return
	var building: Building = cell.get_building()
	var building_actor_scene: PackedScene = preload("res://runtime/frontend/actors/building_actor.tscn")
	return _place_actor(in_axis, building, building_actor_scene, building_actors, building_actors_pool)
	
