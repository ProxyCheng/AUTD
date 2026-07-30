extends Node
class_name Level

var map: Map
var room: Room

static var current: Level = null

func _init():
	map = Map.new()
	map.name = "Map"
	add_child(map)
	room = Room.new()
	room.name = "Room"
	add_child(room)

func _ready():
	map.owner = owner
	room.owner = owner

func load_data(in_data: LevelData):
	var map_data = in_data.map
	map.load_data(map_data)

func tick(in_delta: float):
	map.tick(in_delta)
	room.tick(in_delta)
