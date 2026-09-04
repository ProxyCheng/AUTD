class_name Bag
extends Node

static var next_id: int = 1
var id: int = 0
var item_type: String = ""
var capacity: int = 10
var disired_min_count: int = 0
var disired_max_count: int = capacity
var count: int = 0

signal count_changed()

func _init():
	id = next_id
	next_id += 1
