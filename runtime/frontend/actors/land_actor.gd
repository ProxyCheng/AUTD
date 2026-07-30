extends Node3D
class_name LandActor

var land: Land = null
var type: String = ""
var axis: Vector2i = Vector2i.ZERO

func bind(in_land: Land):
	land = in_land
	if land.type != type:
		type = land.type
		_on_type_changed()
	if land.axis != axis:
		axis = land.axis
		_on_axis_changed()

func _on_type_changed():
	var path = "res://runtime/frontend/textures/land_%s.png" % type
	var texture = null
	if ResourceLoader.exists(path):
		texture = load(path) as CompressedTexture2D
	%displayer.mesh.material.albedo_texture = texture

func _on_axis_changed():
	position = Vector3(axis.x, 0, axis.y)

func get_type_key():
	return "land_%s" % type
