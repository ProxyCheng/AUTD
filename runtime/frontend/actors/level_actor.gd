@tool
extends Node
class_name Level

func load_data(in_data: LevelData):
	var map_data = in_data.map
	%map.load_data(map_data)
