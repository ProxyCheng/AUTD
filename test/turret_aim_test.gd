extends SceneTree

# 炮塔瞄准回归:建筑旋转后,炮口必须仍指向 backend 给的**世界**方向。
#
# 回归背景:建筑朝向由 BuildingActor 对整个模型 look_at 实现(见
# BuildingActor._on_direction_changed),模型局部系随之旋转;而 backend 的
# aim_direction 恒为世界空间向量。TurretModel 若把世界 yaw 直接写进局部的
# %cog_top.rotation.z,建筑朝向就会被重复计入一次 —— 建筑每转 90°,炮塔偏 90°。
#
# 本测试走真实链路:Map.place_building 落一个带 direction 的弩炮 →
# BuildingActor.bind(经 look_at 旋转) → 改 backend aim_direction(信号) →
# TurretModel.set_aim_direction,再量炮管的实际世界朝向。炮管在 rest 位沿
# body 局部 -Y 且水平(见 AGENTS.md §6 / TurretModel),故取
# -body.global_transform.basis.y 为炮口世界朝向。
#
#   <godot.exe> --path <项目根> --headless --script res://test/turret_aim_test.gd
#
# 退出码 = 失败项数(0 = 全过)。

const ACTOR_PATH: String = "res://runtime/frontend/actors/building_actor.tscn"
const MAP_SIZE: int = 8
const PLACE_AXIS: Vector2i = Vector2i(4, 4)
# 炮口世界朝向与 aim_direction 的允许夹角(度)。朝向只做 90° 整数倍旋转,无累积
# 误差,容差取得很小,以便捕捉"整体偏掉一整格"这类回归。
const TOLERANCE_DEG: float = 1.0

# [建筑朝向, 瞄准方向] —— 瞄准方向即 backend aim_direction 的语义(世界 XZ)。
const CASES: Array = [
	[Vector2i.UP, Vector2(0, -1)],
	[Vector2i.UP, Vector2(1, 1)],
	[Vector2i.RIGHT, Vector2(1, 0)],
	[Vector2i.RIGHT, Vector2(-1, 0)],
	[Vector2i.DOWN, Vector2(0, 1)],
	[Vector2i.DOWN, Vector2(1, -1)],
	[Vector2i.LEFT, Vector2(-1, 0)],
	[Vector2i.LEFT, Vector2(0, -1)],
]

var failed: int = 0
var level: Level = null

func _build_level() -> Level:
	var lvl := Level.new()
	root.add_child(lvl)
	Level.current = lvl
	var map_data := MapData.new()
	map_data.size = Vector2i(MAP_SIZE, MAP_SIZE)
	map_data.cells = []
	for r in range(MAP_SIZE):
		var row := CellRowData.new()
		row.cells = []
		for c in range(MAP_SIZE):
			var cell := CellData.new()
			var land := LandData.new()
			land.type = "dirt"
			cell.land = land
			row.cells.append(cell)
		map_data.cells.append(row)
	lvl.map.load_data(map_data)
	return lvl

func _check(in_label: String, in_ok: bool):
	print("CASE ", in_label, " ok=", in_ok)
	if not in_ok:
		failed += 1

func _init():
	_run()

func _run() -> void:
	level = _build_level()
	# Level 挂进 root 后先等一帧:root 就绪后,后续 add_child 的建筑才会自动跑 _ready
	# (在 _init 里同步 add_child 时 SceneTree.root 尚未就绪,见 conveyor_test)。
	await process_frame

	var actor: BuildingActor = (load(ACTOR_PATH) as PackedScene).instantiate()
	root.add_child(actor)
	await process_frame

	for entry: Array in CASES:
		var building_direction: Vector2i = entry[0]
		var aim: Vector2 = entry[1]
		aim = aim.normalized()
		var data := BuildingData.new()
		data.type = "crossbow"
		data.direction = building_direction
		var building: Building = level.map.place_building(PLACE_AXIS, data, false)
		actor.bind(building)
		# backend 只给世界方向;信号经 BuildingActor 转发给 TurretModel
		building.aim_direction = aim
		await process_frame

		var body: Node3D = actor.building_model.get_node("base/cog_top/deck/bracket/body")
		var barrel: Vector3 = -body.global_transform.basis.y.normalized()
		var want: Vector3 = Vector3(aim.x, 0, aim.y)
		var err_deg: float = rad_to_deg(barrel.angle_to(want))
		_check("dir=%s aim=(%.2f,%.2f) barrel=(%.2f,%.2f) err=%.2fdeg" % [
				building_direction, aim.x, aim.y, barrel.x, barrel.z, err_deg],
				err_deg <= TOLERANCE_DEG)

		actor.bind(null)
		level.map.remove_building(PLACE_AXIS)
		await process_frame

	Level.current = null      # 静态指针不置空会留到退出,报一堆 ObjectDB 泄漏
	print("RESULT failed=", failed)
	quit(failed)
