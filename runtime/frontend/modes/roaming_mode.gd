class_name RoamingMode
extends Mode

# 漫游模式:自由探索 + 点选检视目标(建筑或工人)。
# 桌面 B 键 / 屏幕 Build 按钮切到建造模式;点击世界经 LevelActor.pick_target 统一拾取
# (建筑与工人同做射线-AABB,最近命中者胜),命中即经 inspect_target 打开 GUI 面板。

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
	# 建筑与工人由同一套射线-AABB 判定(见 LevelActor.pick_target),不再按落点格找建筑。
	var target: Object = owner.pick_target(in_screen_position)
	if target:
		owner.inspect_target(target)

func _on_build_pressed():
	owner.set_mode(&"building")
