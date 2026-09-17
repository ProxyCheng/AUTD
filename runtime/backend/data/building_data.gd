@tool
extends Resource
class_name BuildingData

@export
var type: String = ""
@export
var direction: Vector2i = Vector2i.UP
# 调度优先级(1-9,默认 5):同一数值同时驱动本建筑的顶岗优先级与其需求仓的补货优先级
# ("重要建筑既优先派人、也优先补料"),由 Building.priority 可观察属性读写(§5.4)。
@export
var priority: int = 5
