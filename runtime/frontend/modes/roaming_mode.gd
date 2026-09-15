class_name RoamingMode
extends Mode

# 漫游模式:自由探索 + 点选已放置建筑打开检视面板。
# 桌面 B 键 / 屏幕 Build 按钮切到建造模式;点击落点格若有建筑,经
# LevelActor.inspect_building 打开 GUI 面板。

func _ready():
	$ui.hide()
	$ui/build_button.pressed.connect(_on_build_pressed)

func enter():
	$ui.show()

func leave():
	$ui.hide()

func tick(_in_delta: float):
	if Input.is_key_pressed(KEY_B):
		owner.set_mode(&"building")

func on_tap(in_screen_position: Vector2):
	var axis: Variant = get_pointing_axis(in_screen_position)
	if axis == null:
		return
	var map: Map = Level.current.map
	var cell: Cell = map.get_cell(axis)
	if not cell or not cell.building:
		return
	owner.inspect_building(cell.building)

func _on_build_pressed():
	owner.set_mode(&"building")
