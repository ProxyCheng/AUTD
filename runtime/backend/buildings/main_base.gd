class_name MainBase
extends Building

static var current: MainBase = null

func _init():
	current = self

func _ready():
	for i in range(3):
		var labor = Entity.create("labor")
		labor.position = Vector2(axis.x, axis.y)
		Level.current.room.add_entity(labor)
