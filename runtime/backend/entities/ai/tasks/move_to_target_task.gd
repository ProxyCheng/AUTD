class_name MoveToTargetTask
extends BTAction

# 朝"目标圆"匀速行走:目标 = 以 (target_position + arrival_center_offset) 为圆心、
# arrival_distance 为半径的圆。工人沿最短路径直线逼近,进入圆内即 SUCCESS(停在圆边上)。
#   arrival_center_offset = Vector2 圆心相对参考点(target_position)的偏移:
#     0 → 圆心即参考点本身。
#   arrival_distance = float 圆半径(到达范围):
#     0 → 精确到达圆心(旧行为);>0 → 进入该半径的圆即视为到达。
# 典型用法:
#   man_building   参考点=建筑中心,圆心偏移到操作角、半径 0 → 精确站到角上;
#   transport_haul 参考点=建筑中心,圆心偏移 0、半径 0.5(格内切圆)→ 走到建筑范围内即可。
# 每次 _tick 只消费传入的 delta(get_move_speed() * delta 步长),固定短 tick 语义。

@export var target_var: StringName = &"target_position"
# 目标圆圆心相对 target_position 的偏移(Vector2)
@export var arrival_center_offset: Vector2 = Vector2.ZERO
# 目标圆半径(到达范围):0 = 精确到达圆心
@export_range(0.0, 5.0, 0.05) var arrival_distance: float = 0.0

func _enter():
	var entity := get_agent() as Entity
	if not entity:
		return
	entity.state = "walk"
	var center := _target_center(entity)
	var offset := center - entity.position
	if offset.length() > 0.001:
		entity.direction = offset.normalized()

func _tick(in_delta: float) -> int:
	var entity := get_agent() as Entity
	if not entity:
		return BT.Status.FAILURE
	if entity.get_move_speed() <= 0:
		return BT.Status.FAILURE
	var center := _target_center(entity)
	var distance := entity.position.distance_to(center)
	# 剩余要走的路程 = 当前距离 - 圆半径(圆心在圆内即停在边上);在圆内即成功
	var travel := maxf(distance - arrival_distance, 0.0)
	if travel <= 0.001:
		return BT.Status.SUCCESS
	var step := entity.get_move_speed() * in_delta
	if step >= travel:
		# 正好停在圆边界,不越过圆心
		entity.position = entity.position.move_toward(center, travel)
		return BT.Status.SUCCESS
	entity.position = entity.position.move_toward(center, step)
	return BT.Status.RUNNING

# 目标圆圆心 = 黑板上参考点(可能为 Vector2i/Vector2)+ 中心偏移
func _target_center(in_entity: Entity) -> Vector2:
	var raw = get_blackboard().get_var(target_var, in_entity.position)
	if raw is Vector2i:
		return Vector2(raw) + arrival_center_offset
	return raw + arrival_center_offset
