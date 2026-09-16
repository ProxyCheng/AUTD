class_name BuildingMode
extends Mode

var building_data: BuildingData = null
var building_model: Node3D = null

func _ready():
	$ui.hide()
	$ui/back_button.pressed.connect(_on_back_pressed)
	$ui/cards/card_crossbow.clicked.connect(func(): _on_card_clicked("crossbow"))
	$ui/cards/card_stockpile.clicked.connect(func(): _on_card_clicked("stockpile"))
	$ui/cards/card_tree_workshop.clicked.connect(func(): _on_card_clicked("tree_workshop"))
	$ui/cards/card_stone_mine.clicked.connect(func(): _on_card_clicked("stone_mine"))
	$ui/cards/card_crafting_workshop.clicked.connect(func(): _on_card_clicked("crafting_workshop"))
	$ui/cards/card_tool_workshop.clicked.connect(func(): _on_card_clicked("tool_workshop"))
	$ui/cards/card_cannon.clicked.connect(func(): _on_card_clicked("cannon"))

func enter():
	$ui.show()

func tick(_in_delta: float):
	if Input.is_key_pressed(KEY_ESCAPE):
		owner.set_mode(&"roaming")
		return
	_update_preview()

# 点击世界放置建筑(触屏 tap / 鼠标左键)。放在这里而非 tick 轮询,以区分
# "拖动相机"与"点击落库"。
func on_tap(in_screen_position: Vector2):
	if not building_model or not building_data:
		return
	var axis: Variant = get_pointing_axis(in_screen_position)
	if axis == null:
		return
	var map: Map = Level.current.map
	if not map.can_place_building(axis, building_data):
		AudioManager.sfx(&"ui_error")
		return
	map.place_building(axis, building_data)
	AudioManager.sfx_at(&"build_place", Vector3(axis.x, 0, axis.y))

# 桌面鼠标悬停预览(触屏无 hover,预览停在最后一次点击格);不可放置时隐藏。
func _update_preview():
	if not building_model or not building_data:
		return
	var axis: Variant = get_pointing_axis(get_viewport().get_mouse_position())
	if axis == null:
		building_model.hide()
		return
	var map: Map = Level.current.map
	if not map.can_place_building(axis, building_data):
		building_model.hide()
		return
	building_model.position = Vector3(axis.x, 0, axis.y)
	building_model.show()

func leave():
	if building_model:
		building_data = null
		remove_child(building_model)
		building_model.queue_free()
		building_model = null
	$ui.hide()

func _on_back_pressed():
	owner.set_mode(&"roaming")

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
