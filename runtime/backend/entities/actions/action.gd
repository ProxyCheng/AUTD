class_name Action
extends Node

var entity: Entity = null

func set_entity(in_entity: Entity):
	entity = in_entity

func enter():
	pass

func tick(in_delta: float) -> ActionStatus:
	return ActionStatus.success(0)

func leave():
	pass
