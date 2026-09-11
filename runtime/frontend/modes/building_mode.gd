class_name BuildingMode
extends Mode

var building_data: BuildingData = null
var building_model: Node3D = null

func _ready():
	$"ui".hide()
	$ui/cards/card_crossbow.clicked.connect(func(): _on_card_clicked("crossbow"))
	$ui/cards/card_stockpile.clicked.connect(func(): _on_card_clicked("stockpile"))
	$ui/cards/card_tree_workshop.clicked.connect(func(): _on_card_clicked("tree_workshop"))
	$ui/cards/card_stone_mine.clicked.connect(func(): _on_card_clicked("stone_mine"))
	$ui/cards/card_crafting_workshop.clicked.connect(func(): _on_card_clicked("crafting_workshop"))

func enter():
	$"ui".show()

func tick(in_delta: float):
	if Input.is_key_pressed(KEY_ESCAPE):
		owner.set_mode(&"roaming")
		return
	var axis = get_pointing_axis()
	if axis == null:
		return
	var map: Map = Level.current.map
	if building_model:
		if not map.can_place_building(axis, building_data):
			building_model.hide()
			return
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _is_pointer_over_ui():
			map.place_building(axis, building_data)
			return
		building_model.position = Vector3(axis.x, 0, axis.y)
		building_model.show()
	
# 指针是否停在 UI(建筑选择面板等)上;是则不落库,避免"点面板的同时把建筑放到面板后的地面"。
func _is_pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func get_pointing_axis():
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d()
	var mouse_position: Vector2 = viewport.get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mouse_position)
	var direction: Vector3 = camera.project_ray_normal(mouse_position)
	var hit_position = ray_intersects_y0(origin, direction)
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
		building_data = null
		remove_child(building_model)
		building_model.queue_free()
		building_model = null
	$"ui".hide()

func _on_card_clicked(in_building_type: String):
	if in_building_type == (building_data.type if building_data else ""):
		return
	building_data = BuildingData.new()
	building_data.type = in_building_type
	if building_model:
		remove_child(building_model)
		building_model.queue_free()
		building_model = null
	var building_path: String = "res://runtime/frontend/models/buildings/%s/%s.tscn" % [building_data.type, building_data.type]
	var building_scene: PackedScene = load(building_path)
	building_model = building_scene.instantiate()
	add_child(building_model)
	building_model.owner = owner
	building_model.hide()
