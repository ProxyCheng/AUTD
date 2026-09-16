class_name RoamingMode
extends Mode

# 漫游模式:自由探索 + 点选检视目标(建筑或工人)。
# 桌面 B 键 / 屏幕 Build 按钮切到建造模式;点击世界先做实体拾取(工人等),
# 未命中再按落点格找建筑,统一经 LevelActor.inspect_target 打开 GUI 面板。

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
	# 实体优先:地面射线可能打不到(点中远处天空/建筑侧面),但实体 AABB 仍可命中;
	# 且工人比格子小,必须按最近命中判定,不能退化成格子级点选。
	var entity: Entity = owner.pick_entity(in_screen_position)
	if entity:
		owner.inspect_target(entity)
		return
	var axis: Variant = get_pointing_axis(in_screen_position)
	if axis == null:
		return
	var map: Map = Level.current.map
	var cell: Cell = map.get_cell(axis)
	if not cell or not cell.building:
		return
	owner.inspect_target(cell.building)

func _on_build_pressed():
	owner.set_mode(&"building")
