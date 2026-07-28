@tool
extends Resource
class_name FloorData

@export
var type: String:
	set(value):
		type = value
		emit_changed()
