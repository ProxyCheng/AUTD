class_name LevelActor
extends Node

@export
var level_data: LevelData

@export
var speed: float = 1

var level: Level = null
var mode: Mode = null

func bind(in_level: Level):
	level = in_level
	level.owner = owner
	add_child(level)
	%map.bind(level.map)
	%room.bind(level.room)

func get_camera():
	return %camera

func set_mode(in_mode_id: StringName):
	if mode:
		mode.leave()
		mode = null
	for m in %modes.get_children():
		if m.name == in_mode_id:
			mode = m as Mode
			break
	if mode:
		mode.enter()

func _ready():
	assert(level_data)
	bind(Level.new())
	Level.current = level
	level.load_data(level_data)
	
	set_mode(&"roaming")

func _process(in_delta: float):
	level.tick(in_delta * speed)
	if mode:
		mode.tick(in_delta)
	else:
		set_mode(&"roaming")
