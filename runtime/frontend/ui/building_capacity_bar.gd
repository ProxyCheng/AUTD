class_name BuildingCapacityBar
extends HeadBar

# 容量条:值 = 建筑的 Bag 占用率(occupancy_fill);无 Bag(occupancy_fill 为负)不显示。
# 复用 HeadBar 的 billboard 定位、头顶高度测量与显隐;这里只提供数据源。

const COLOR_CAPACITY: Color = Color(0.25, 0.55, 0.95, 0.95)

var building: Building = null

func configure(in_building: Building):
	building = in_building
	if building:
		set_fill_color(COLOR_CAPACITY)
	else:
		hide()

func _value() -> float:
	if not building:
		return -1.0
	return building.occupancy_fill()
