@tool
extends MeshInstance3D
class_name FloorActor

@export
var data: FloorData

func load_data(in_data: FloorData):
	data = in_data
	refresh()
	data.changed.connect(refresh)

func refresh():
	var path = "res://runtime/frontend/textures/floor_%s.png" % data.type
	var texture: CompressedTexture2D
	if ResourceLoader.exists(path):
		texture = load(path)
	mesh.material.albedo_texture = texture
