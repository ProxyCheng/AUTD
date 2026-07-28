extends Node3D

@export
var level: LevelData

func _ready() -> void:
	assert(level)
	%level.load_data(level)
