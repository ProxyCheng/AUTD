extends Node
class_name Level

var map: Map
var room: Room
var labor_manager: LaborManager
var logistics: Logistics

static var current: Level = null

func _init():
	map = Map.new()
	map.name = "Map"
	add_child(map)
	room = Room.new()
	room.name = "Room"
	add_child(room)
	logistics = Logistics.new()
	logistics.name = "Logistics"
	add_child(logistics)
	labor_manager = LaborManager.new()
	labor_manager.name = "LaborManager"
	add_child(labor_manager)

func _ready():
	map.owner = owner
	room.owner = owner
	logistics.owner = owner
	labor_manager.owner = owner

func load_data(in_data: LevelData):
	var map_data = in_data.map
	map.load_data(map_data)

func tick(in_delta: float):
	map.tick(in_delta)
	room.tick(in_delta)
