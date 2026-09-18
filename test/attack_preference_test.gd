extends SceneTree

# AttackBuilding 攻击偏好测试:front/last 的"前后轴"必须以主基地为锚,不能写死某个坐标轴。
#
#   <godot.exe> --path <项目根> --headless --script res://test/attack_preference_test.gd
#
# 退出码 = 失败项数(0 = 全过)。
#
# 回归背景:front/last 原先按 position.y 排序(注释写"y 越负越前"),但 level0 的敌人生成器
# 与主基地同在 y=4 一行、敌人沿 +x 推进 ⇒ 所有敌人 y 相同 ⇒ 排序退化为常数比较
# ⇒ front 与 last 取到同一个敌人(实测:两个档位都在打最后一个敌人)。
# 修复后改用"到主基地的距离平方"排序 —— 与关卡朝向无关。
#
# 本测试刻意把两个敌人放在同一行(y 相同),这正是旧实现失效的几何。

const ROW: int = 4
const BASE_X: int = 8     # 主基地
const TOWER_X: int = 4    # 弩炮
const FRONT_X: int = 6    # 离主基地近 ⇒ 最前
const BACK_X: int = 2     # 离主基地远 ⇒ 末尾

func _build_level() -> Level:
	var level := Level.new()
	root.add_child(level)
	Level.current = level

	var map_data := MapData.new()
	map_data.size = Vector2i(10, 10)
	map_data.cells = []
	for r in range(10):
		var row := CellRowData.new()
		row.cells = []
		for c in range(10):
			var cell := CellData.new()
			var land := LandData.new()
			land.type = "dirt"
			cell.land = land
			row.cells.append(cell)
		map_data.cells.append(row)
	level.map.load_data(map_data)
	return level

func _place_tower(in_level: Level) -> Crossbow:
	var bd := BuildingData.new()
	bd.type = "crossbow"
	bd.direction = Vector2i.UP
	return in_level.map.place_building(Vector2i(TOWER_X, ROW), bd, true) as Crossbow

# 主基地只作 front/last 的锚点:不进树 ⇒ 不触发 MainBase._ready(不建仓、不生 20 个工人),
# 但 _init() 已把 MainBase.current 指向它,load_data 后 axis 有效 —— find_target 只需要这些。
func _anchor_base(in_level: Level) -> MainBase:
	var bd := BuildingData.new()
	bd.type = "main_base"
	var base := MainBase.new()
	base.load_data(bd, in_level.map.get_cell(Vector2i(BASE_X, ROW)))
	return base

func _spawn_enemy(in_level: Level, in_x: int) -> Enemy:
	var enemy: Enemy = Entity.create("slime") as Enemy
	enemy.position = Vector2(in_x, ROW)
	in_level.room.add_entity(enemy)
	return enemy

func _init():
	var failed: int = 0
	var level: Level = _build_level()
	var tower: Crossbow = _place_tower(level)
	var base: MainBase = _anchor_base(level)
	var front_enemy: Enemy = _spawn_enemy(level, FRONT_X)
	var back_enemy: Enemy = _spawn_enemy(level, BACK_X)
	print("setup tower=", tower.axis, " base=", base.axis,
		" front=", front_enemy.position, " back=", back_enemy.position,
		" range=", tower.get_attack_range())

	# —— front:离主基地更近的那个 ——
	tower.set_target_preference(AttackBuilding.TARGET_PREF_FRONT)
	var picked_front: Entity = tower.find_target()
	print("front picked=", picked_front.position if picked_front else null, " expect=", front_enemy.position)
	if picked_front != front_enemy:
		failed += 1

	# —— last:离主基地更远的那个 ——
	tower.set_target_preference(AttackBuilding.TARGET_PREF_LAST)
	var picked_last: Entity = tower.find_target()
	print("last  picked=", picked_last.position if picked_last else null, " expect=", back_enemy.position)
	if picked_last != back_enemy:
		failed += 1

	# —— 两者必须不同:同一行上旧实现会取到同一个(常数比较),本断言直接钉住该回归 ——
	if picked_front == picked_last:
		print("front/last picked the SAME enemy -> axis regression")
		failed += 1

	# 锚点主基地没进树,不会被场景树回收 —— 显式释放,避免退出时报 ObjectDB 泄漏。
	base.free()
	print("RESULT failed=", failed)
	quit(failed)
