extends Node

@export
var level_data: LevelData

var level: Level

func bind(in_level: Level):
	level = in_level
	level.owner = self
	add_child(level)
	%map.bind(level.map)
	%room.bind(level.room)

func _ready():
	assert(level_data)
	bind(Level.new())
	Level.current = level
	level.load_data(level_data)

func _process(in_delta: float):
	level.tick(in_delta)
