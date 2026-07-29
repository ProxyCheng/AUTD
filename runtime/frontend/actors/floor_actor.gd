extends Node3D
class_name FloorActor

var floor: Floor = null
var type: String = ""
var axis: Vector2i = Vector2i.ZERO

func bind(in_floor: Floor):
	floor = in_floor
	if floor.type != type:
		type = floor.type
		on_type_changed()
	if floor.axis != axis:
		axis = floor.axis
		on_axis_changed()

func on_type_changed():
	var path = "res://runtime/frontend/textures/floor_%s.png" % type
	var texture = null
	if ResourceLoader.exists(path):
		texture = load(path) as CompressedTexture2D
	%displayer.mesh.material.albedo_texture = texture

func on_axis_changed():
	position = Vector3(axis.x, 0, axis.y)

func get_type_key():
	return "floor_%s" % type
