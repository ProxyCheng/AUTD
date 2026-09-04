class_name Labor
extends Creature

var brain: Brain = null
var brain_type: StringName = ""

func _init():
	super._init()
	move_speed = 1
	set_brain(&"courier")

func create_action() -> Action:
	return brain.create_action()

func set_brain(in_brain_type: StringName):
	if in_brain_type == brain_type:
		return
	brain_type = in_brain_type
	if brain:
		brain.leave()
		remove_child(brain)
		brain.queue_free()
		brain = null
	var brain_class: GDScript = load("res://runtime/backend/entities/brains/%s_brain.gd" % brain_type)
	assert(brain_class, "Failed to load brain %s" % brain_type)
	brain = brain_class.new(self)
	add_child(brain)
	brain.owner = owner
	brain.enter()
