class_name MoveToTargetTask
extends BTAction

# 朝黑板上记录的 target_position 匀速行走。
# 每次 _tick 只消费传入的 delta(move_speed * delta 步长),到达即 SUCCESS;
# 不再有"剩余时间溢出给下一个动作"的语义,调用方保证固定短 tick。

@export var target_var: StringName = &"target_position"

func _enter():
	var entity := get_agent() as Entity
	if not entity:
		return
	entity.state = "walk"
	var target := _target_of(entity)
	var offset := target - entity.position
	if offset.length() > 0.001:
		entity.direction = offset.normalized()

func _tick(in_delta: float) -> int:
	var entity := get_agent() as Entity
	if not entity:
		return BT.Status.FAILURE
	if entity.move_speed <= 0:
		return BT.Status.FAILURE
	var target := _target_of(entity)
	var distance := entity.position.distance_to(target)
	var step := entity.move_speed * in_delta
	if step >= distance:
		entity.position = target
		return BT.Status.SUCCESS
	entity.position = entity.position.move_toward(target, step)
	return BT.Status.RUNNING

func _target_of(in_entity: Entity) -> Vector2:
	return get_blackboard().get_var(target_var, in_entity.position)
