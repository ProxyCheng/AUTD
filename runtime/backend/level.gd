class_name Level

var map: Map = Map.new()
var room: Room = Room.new()

static var current: Level = null

func load_data(in_data: LevelData):
	var map_data = in_data.map
	map.load_data(map_data)

func tick(in_delta: float):
	map.tick(in_delta)
	room.tick(in_delta)
