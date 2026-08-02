class_name BuildingMode
extends Mode

var building_model: Node3D = null

func _ready():
	$"ui".hide()
	$ui/cards/card_crossbow.clicked.connect(func(): _on_card_clicked("crossbow"))

func enter():
	$"ui".show()

func tick(in_delta: float):
	if Input.is_key_pressed(KEY_ESCAPE):
		owner.set_mode(&"roaming")
	var axis: Vector2i = get_pointing_axis()
	var cell: Cell = Level.current.map.get_cell(axis)
	if building_model:
		if not cell:
			building_model.hide()
			return
		building_model.position = Vector3(axis.x, 0, axis.y)
		building_model.show()
	
func get_pointing_axis():
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d()
	var mouse_position: Vector2 = viewport.get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mouse_position)
	var direction: Vector3 = camera.project_ray_normal(mouse_position)
	var hit_position: Vector3 = ray_intersects_y0(origin, direction)
	if not hit_position:
		return null
	return Vector2i(round(hit_position.x), round(hit_position.z))

func ray_intersects_y0(in_origin: Vector3, in_direction: Vector3):
	if is_zero_approx(in_direction.y):
		return null
	var t: float = -in_origin.y / in_direction.y
	if t < 0:
		return null
	return in_origin + in_direction * t

func leave():
	if building_model:
		remove_child(building_model)
		building_model.queue_free()
		building_model = null
	$"ui".hide()

func _on_card_clicked(in_building_id: String):
	if building_model:
		remove_child(building_model)
		building_model.queue_free()
		building_model = null
	var building_path: String = "res://runtime/frontend/models/buildings/%s/%s.tscn" % [in_building_id, in_building_id]
	var building_scene: PackedScene = load(building_path)
	building_model = building_scene.instantiate()
	add_child(building_model)
	building_model.owner = owner
	building_model.hide()
