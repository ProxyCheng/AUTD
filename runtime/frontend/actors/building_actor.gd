extends Node3D
class_name BuildingActor

var building: Building = null
var type: String = ""
var building_model: Node3D = null
var axis: Vector2i = Vector2i.ZERO
var direction: Vector2i = Vector2i.UP

@onready var capacity_bar: BuildingCapacityBar = %capacity_bar

func bind(in_building: Building):
	if building:
		building.state_changed.disconnect(_on_building_state_changed)
		building.progress_changed.disconnect(_on_building_progress_changed)
		if building.has_signal(&"aim_direction_changed"):
			building.aim_direction_changed.disconnect(_on_building_aim_direction_changed)
		if building.has_signal(&"content_type_changed"):
			building.content_type_changed.disconnect(_on_building_content_type_changed)
		if building.has_signal(&"stored_count_changed"):
			building.stored_count_changed.disconnect(_on_building_stored_count_changed)
	building = in_building
	if not building:
		capacity_bar.configure(null)
		return
	if building.type != type:
		type = building.type
		_on_type_changed()
	if building.axis != axis:
		axis = building.axis
		_on_axis_changed()
	if building.direction != direction:
		direction = building.direction
		_on_direction_changed()
	building.state_changed.connect(_on_building_state_changed)
	building.progress_changed.connect(_on_building_progress_changed)
	if building.has_signal(&"aim_direction_changed"):
		building.aim_direction_changed.connect(_on_building_aim_direction_changed)
	if building.has_signal(&"content_type_changed"):
		building.content_type_changed.connect(_on_building_content_type_changed)
	if building.has_signal(&"stored_count_changed"):
		building.stored_count_changed.connect(_on_building_stored_count_changed)
	capacity_bar.configure(building)
	_on_building_state_changed()
	_on_building_progress_changed()
	_on_building_aim_direction_changed()
	_on_building_content_type_changed()
	_on_building_stored_count_changed()
	_update_direction()

func get_type_key() -> String:
	return "Building_%s" % type

func _on_type_changed():
	if building_model:
		remove_child(building_model)
		building_model.queue_free()
	var building_path: String = "res://runtime/frontend/models/buildings/%s/%s.tscn" % [type, type]
	var building_scene: PackedScene = load(building_path)
	building_model = building_scene.instantiate()
	if building_model:
		add_child(building_model)
		building_model.owner = owner
		capacity_bar.setup(self, building_model)

func _on_axis_changed():
	position = Vector3(axis.x, 0, axis.y)

func _on_direction_changed():
	look_at(global_position + Vector3(direction.x, 0, direction.y))

func _process(_delta: float):
	_update_direction()
# 水平朝向:跟随 backend 的 aim_direction(信号驱动)
func _on_building_aim_direction_changed():
	if not building_model:
		return
	if not building_model.has_method(&"set_aim_direction"):
		return
	if not building or not building.has_signal(&"aim_direction_changed"):
		return
	var aim: Vector2 = building.aim_direction
	building_model.set_aim_direction(Vector3(aim.x, 0, aim.y))

# 俯仰:每帧按目标距离调整,无需信号
func _update_direction():
	if not building_model:
		return
	if not building_model.has_method(&"set_target_position"):
		return
	if not building:
		return
	if not building.target:
		return
	var target_position = building.target.position
	building_model.set_target_position(Vector3(target_position.x, 0, target_position.y))

func _on_building_state_changed():
	if not building:
		return
	if not building_model:
		return
	if not building_model.has_method(&"set_state"):
		return
	building_model.set_state(building.state)

func _on_building_progress_changed():
	if not building:
		return
	if not building_model:
		return
	if not building_model.has_method(&"set_progress"):
		return
	building_model.set_progress(building.progress)

# 料堆等存储型建筑:物品类型变化 → model 换内容物模型
func _on_building_content_type_changed():
	if not building:
		return
	if not building_model:
		return
	if not building_model.has_method(&"set_content_type"):
		return
	if not building.has_signal(&"content_type_changed"):
		return
	building_model.set_content_type(building.content_type)

# 料堆等存储型建筑:存量变化 → model 按 count/capacity 更新堆叠量
func _on_building_stored_count_changed():
	if not building:
		return
	if not building_model:
		return
	if not building_model.has_method(&"set_stored_count"):
		return
	if not building.has_signal(&"stored_count_changed"):
		return
	building_model.set_stored_count(building.stored_count, building.capacity)
