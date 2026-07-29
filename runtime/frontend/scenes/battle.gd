extends Node3D

@export
var level_data: LevelData

var level: Level

func bind(in_level: Level):
	level = in_level
	%map.bind(level.map)

func _ready():
	assert(level_data)
	bind(Level.new())
	level.load_data(level_data)
