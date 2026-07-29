class_name Level

var map: Map = Map.new()

func load_data(in_data: LevelData):
	var map_data = in_data.map
	map.load_data(map_data)
