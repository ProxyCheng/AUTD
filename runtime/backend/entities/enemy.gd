class_name Enemy
extends Creature

# 敌人默认树:Sequence[ 走向主基地, 抵达即自毁 ]。存于 runtime/backend/entities/ai/。

const TARGET_POSITION_VAR: StringName = &"target_position"
const BEHAVIOR_TREE_PATH := "res://runtime/backend/entities/ai/enemy_siege.tres"

func create_tree() -> BehaviorTree:
	blackboard.set_var(TARGET_POSITION_VAR, MainBase.current.axis if MainBase.current else Vector2.ZERO)
	var tree: BehaviorTree = load(BEHAVIOR_TREE_PATH)
	if tree == null:
		return _build_enemy_tree()
	return tree

func _build_enemy_tree() -> BehaviorTree:
	var move_task := MoveToTargetTask.new()
	var attack_task := EnemyAttackTask.new()
	var sequence := BTSequence.new()
	sequence.add_child(move_task)
	sequence.add_child(attack_task)
	var tree := BehaviorTree.new()
	tree.set_root_task(sequence)
	return tree
