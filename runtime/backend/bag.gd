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

# 入库:按剩余空间接受 in_amount 个,返回实际入库数(超容部分丢弃)。
func add_count(in_amount: int) -> int:
	var accepted: int = mini(in_amount, capacity - count)
	if accepted <= 0:
		return 0
	count += accepted
	count_changed.emit()
	return accepted

# 出库:按当前存量吐出 in_amount 个,返回实际出库数(不足部分少给)。
func remove_count(in_amount: int) -> int:
	var removed: int = mini(in_amount, count)
	if removed <= 0:
		return 0
	count -= removed
	count_changed.emit()
	return removed
