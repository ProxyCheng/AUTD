class_name Logistics
extends Node

enum BagState{
	Satisified,
	Understocked,
	Overstocked,
}

var bags: Dictionary = {}  # { bag_id: bag }
var changed_bags: Dictionary = {}  # { bag_id: true }
var transactions: Dictionary = {}  # { bag_id: Transaction }

func register_bag(in_bag: Bag):
	bags.set(in_bag.id, in_bag)
	changed_bags.set(in_bag.id, true)
	in_bag.count_changed.connect(func(): _on_bag_count_changed(in_bag.id))

func unregister_bag(in_bag_id: int):
	bags.erase(in_bag_id)

func tick(in_delta: float):
	if changed_bags.is_empty():
		return
	for bag_id in changed_bags.keys():
		var bag = bags.get(bag_id)
		if not bag:
			continue
		
	changed_bags.clear()

func _on_bag_count_changed(in_bag_id: int):
	changed_bags.set(in_bag_id, true)
