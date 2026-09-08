class_name Bag
extends Node

# 物品仓库(挂在建筑/实体下,由 Logistics 统一调度搬运)。
#
# 三层数量语义:
#   max_count            严格物理上限,count 永不超过它(add_count 按剩余空间截断)。
#   preferred_min_count  舒适下限:count < 该值 → 本 bag 处于"缺货请求"态,希望被补货。
#   preferred_max_count  舒适上限:count > 该值 → 本 bag 处于"富余供给"态,超出部分可外供;
#                        count 达到它即视为"补货完成",不再触发搬运请求。
#   [preferred_min, preferred_max] 之间为舒适区,不参与搬运。
# 纯请求方(bag 自己只进不出):preferred_min = preferred_max = max_count。
# 纯供给方(bag 自己只出不进):preferred_min = preferred_max = 0(有货即外供)。
# 仓储型:preferred_min 为自留警戒线(低于它求补),preferred_max 为外供起点(高于它才出)。
# 注意 preferred_max_count 应 <= max_count。

static var next_id: int = 1
var id: int = 0

var item_type: String = ""
var max_count: int = 10
var preferred_min_count: int = 0
var preferred_max_count: int = max_count
var count: int = 0
# 所属建筑中心(由建筑在创建 bag 后设置,= Vector2(axis)):
# Logistics 匹配按此度量距离;搬运移动以其为直线接近目标,由 transport_haul 的
# MoveToTargetTask.arrival_center_offset 决定"停在距建筑中心固定偏移"的停靠圈。
var access_position: Vector2 = Vector2.ZERO

signal count_changed()

func _init():
	id = next_id
	next_id += 1

# 入库:按剩余空间接受 in_amount 个,返回实际入库数(超出 max_count 部分丢弃)。
func add_count(in_amount: int) -> int:
	var accepted: int = mini(in_amount, max_count - count)
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

func is_understocked() -> bool:
	return count < preferred_min_count

func is_overstocked() -> bool:
	return count > preferred_max_count

func is_full() -> bool:
	return count >= max_count
