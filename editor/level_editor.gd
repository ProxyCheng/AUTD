@tool
extends Node

@export
var level_data: LevelData

@export_tool_button("load level")
var load_level = func():
	%level.load_data(level_data)
