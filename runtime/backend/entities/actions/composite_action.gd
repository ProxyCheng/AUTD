class_name CompositeAction
extends Action

func _init(in_children: Array):
	super._init()
	for child in in_children:
		add_child(child)

func set_entity(in_entity: Entity):
	super.set_entity(in_entity)
	for child: Action in get_children():
		child.set_entity(in_entity)

func _ready():
	for child in get_children():
		child.owner = owner
