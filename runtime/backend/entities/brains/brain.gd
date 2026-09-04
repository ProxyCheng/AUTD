class_name Brain
extends Node

var labor: Labor = null

func _init(in_labor: Labor):
	labor = in_labor
	name = get_script().get_global_name()

func create_action() -> Action:
	# Wandering
	return MoveToAction.new(labor.position + Vector2.from_angle(randf() * 2 * PI))

func enter():
	pass

func leave():
	pass
