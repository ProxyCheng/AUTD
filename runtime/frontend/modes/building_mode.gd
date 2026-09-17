class_name BuildingMode
extends Mode

# 预览模型整体半透的比例(0 = 不透明,1 = 全透明)。
const PREVIEW_TRANSPARENCY: float = 0.5

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
	_apply_preview_transparency(building_model)
	building_model.hide()

# 预览模型整体半透:逐个几何实例设 instance transparency(Forward+ 实例级透明度,
# 会把不透明材质也送进透明通道),不改模型自身材质资源,故不影响正式放置后的外观。
# 半透模型不该投实心影,一并关掉阴影投射。
func _apply_preview_transparency(in_root: Node):
	for child: Node in in_root.find_children("*", "GeometryInstance3D", true, false):
		var geometry: GeometryInstance3D = child
		geometry.transparency = PREVIEW_TRANSPARENCY
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
