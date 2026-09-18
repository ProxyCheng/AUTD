extends SceneTree

# 传送带回归:取货 / 计时运输 / 投送 / 卡住与重试 / 单件承载 / 不抽纯需求仓,
# 外加支撑它的 Bag·Building 搬运能力接口。
#   <godot.exe> --path <项目> --headless --script res://test/conveyor_test.gd
#
# 返回 = 失败项数(0 = 通过)。
#
# 夹具沿用 attack_preference_test 的写法:Level 挂进 root ⇒ 建筑的 _ready 会跑(建仓);
# 地图用 MapData 铺平地,再经 Map.place_building 落建筑。传送带的在途仓刻意不注册
# Logistics,故本测试不需要接 Logistics。

const DELTA: float = 0.05
# 走满一格所需帧数 + 1:取货那一帧只负责装货、不计入行程。按 Conveyor.CELL_TRAVEL_SECONDS
# 推导,故后端改带速时这里自动跟随,测试不会与实现脱节。
const FRAMES_ONE_CELL: int = int(Conveyor.CELL_TRAVEL_SECONDS / DELTA) + 1

var failed: int = 0
var level: Level = null

func _build_level() -> Level:
	var lvl := Level.new()
	root.add_child(lvl)
	Level.current = lvl
	var map_data := MapData.new()
	map_data.size = Vector2i(8, 8)
	map_data.cells = []
	for r in range(8):
		var row := CellRowData.new()
		row.cells = []
		for c in range(8):
			var cell := CellData.new()
			var land := LandData.new()
			land.type = "dirt"
			cell.land = land
			row.cells.append(cell)
		map_data.cells.append(row)
	lvl.map.load_data(map_data)
	return lvl

func _place(in_axis: Vector2i, in_type: String, in_direction: Vector2i) -> Building:
	var bd := BuildingData.new()
	bd.type = in_type
	bd.direction = in_direction
	var building: Building = level.map.place_building(in_axis, bd, true)
	# headless --script 跑时 SceneTree 的 root 尚未就绪(Level 进不了树),_ready 不会自动触发;
	# 手工补一次,让建筑按生产路径建好自己的仓(同 workshop_progress_test 手工建仓的用意)。
	building._ready()
	return building

func _run(in_frames: int):
	for i in in_frames:
		level.tick(DELTA)

func _check(in_label: String, in_ok: bool):
	print("CASE ", in_label, " ok=", in_ok)
	if not in_ok:
		failed += 1

func _init():
	level = _build_level()

	# ===== 1. 取 → 走满一格(1.0s)→ 投 =====
	# 源 = 料堆(仓储型,可存可取);中 = 传送带朝 +X(输出端在东);目标 = 另一个料堆。
	var src := _place(Vector2i(0, 0), "stockpile", Vector2i.RIGHT) as Stockpile
	src.store(5)
	var belt := _place(Vector2i(1, 0), "conveyor", Vector2i.RIGHT) as Conveyor
	var dst := _place(Vector2i(2, 0), "stockpile", Vector2i.RIGHT) as Stockpile
	var src_before: int = src.bag.count
	var dst_before: int = dst.bag.count

	_run(1)
	_check("1a 空载即取一件(源少 1 / 带上 1 / state=working)",
			belt.bag.count == 1 and src.bag.count == src_before - 1 and belt.state == "working")
	_check("1b 刚取到时 progress=0", is_zero_approx(belt.progress))

	_run(FRAMES_ONE_CELL - 1)
	_check("1c 走满一格即投出(目标多 1 / 带上空 / state=idle)",
			dst.bag.count == dst_before + 1 and belt.bag.count == 0 and belt.state == "idle")

	# ===== 2. 输出端为空 ⇒ 卡住,且不再取第二件 =====
	var src2 := _place(Vector2i(0, 1), "stockpile", Vector2i.RIGHT) as Stockpile
	src2.store(5)
	var belt2 := _place(Vector2i(1, 1), "conveyor", Vector2i.RIGHT) as Conveyor
	var src2_before: int = src2.bag.count
	_run(FRAMES_ONE_CELL + 40)
	_check("2a 输出端为空 ⇒ state=blocked,货留在带上", belt2.state == "blocked" and belt2.bag.count == 1)
	_check("2b 卡住时 progress 停在 1", is_equal_approx(belt2.progress, 1.0))
	_check("2c 卡住期间不再取第二件(源只少 1)", src2.bag.count == src2_before - 1)

	# ===== 3. 输出端补上 ⇒ 下一帧即恢复投送 =====
	var dst3 := _place(Vector2i(2, 1), "stockpile", Vector2i.RIGHT) as Stockpile
	var dst3_before: int = dst3.bag.count
	_run(1)
	_check("3  输出端补上后即投出(目标多 1 / 带上空 / state=idle)",
			dst3.bag.count == dst3_before + 1 and belt2.bag.count == 0 and belt2.state == "idle")

	# ===== 4. 目标收不下(满仓)⇒ 卡住,货不丢 =====
	var src4 := _place(Vector2i(0, 2), "stockpile", Vector2i.RIGHT) as Stockpile
	src4.store(5)
	var belt4 := _place(Vector2i(1, 2), "conveyor", Vector2i.RIGHT) as Conveyor
	var dst4 := _place(Vector2i(2, 2), "stockpile", Vector2i.RIGHT) as Stockpile
	dst4.store(Stockpile.CAPACITY)
	_check("4a 目标已满仓", dst4.is_full())
	_run(FRAMES_ONE_CELL + 10)
	_check("4b 目标满仓 ⇒ state=blocked 且货不丢", belt4.state == "blocked" and belt4.bag.count == 1)

	# ===== 5. Bag 搬运能力谓词(传送带取送依赖的判据)=====
	var storage := Bag.new()
	storage.item_type = "arrow"
	storage.max_count = 30
	storage.preferred_min_count = 0
	storage.preferred_max_count = 30
	storage.add_count_of("arrow", 5)
	_check("5a 仓储型:可给、可给量=全部存量、落库档最高(2)",
			storage.can_provide("arrow") and storage.available_to_provide("arrow") == 5 and storage.deposit_rank("arrow") == 2)
	_check("5b 仓储型:可收", storage.can_accept("arrow"))

	var demand := Bag.new()
	demand.item_type = "log"
	demand.max_count = 30
	demand.preferred_min_count = 30
	demand.preferred_max_count = 30
	demand.add_count_of("log", 5)
	_check("5c 纯需求方:不可给(不会被抽走)",
			not demand.can_provide("log") and demand.available_to_provide("log") == 0)
	_check("5d 纯需求方:可收、落库档最高(2)", demand.can_accept("log") and demand.deposit_rank("log") == 2)

	var supply := Bag.new()
	supply.item_type = "arrow"
	supply.max_count = 30
	supply.preferred_min_count = 0
	supply.preferred_max_count = 0
	supply.add_count_of("arrow", 5)
	_check("5e 纯供给方:可给全部、落库档次高(1)",
			supply.can_provide("arrow") and supply.available_to_provide("arrow") == 5 and supply.deposit_rank("arrow") == 1)

	# ===== 6. Building 门面(传送带取送实际走它)=====
	# 单独的料堆:src 在前面几轮里已被自己的传送带抽走不少,不能复用做"可给"断言。
	var lone := _place(Vector2i(1, 3), "conveyor", Vector2i.RIGHT) as Conveyor
	var storage_building := _place(Vector2i(3, 3), "stockpile", Vector2i.RIGHT) as Stockpile
	storage_building.store(5)
	_check("6a 料堆作为建筑:可给且可收",
			storage_building.can_provide("arrow") and storage_building.can_accept("arrow"))
	_check("6b 传送带暴露在途仓,未满即可收(空载也要能收,否则串接会断)",
			lone.get_transfer_bags().size() == 1 and lone.can_accept("arrow"))
	_check("6c 空载传送带不可给", not lone.can_provide("arrow"))

	# ===== 7. 传送带串接:输出端是另一条传送带 =====
	# 上游把货直接推进下游的在途仓;下游据此起表、走满一格再投(不能跳过运输)。
	var src7 := _place(Vector2i(0, 4), "stockpile", Vector2i.RIGHT) as Stockpile
	src7.store(3)
	var src7_before: int = src7.bag.count
	var belt7a := _place(Vector2i(1, 4), "conveyor", Vector2i.RIGHT) as Conveyor
	var belt7b := _place(Vector2i(2, 4), "conveyor", Vector2i.RIGHT) as Conveyor

	_run(FRAMES_ONE_CELL)
	_check("7a 上游把货交给下游(下游带上 1 件)", belt7b.bag.count == 1)
	_check("7b 下游确实开始走(而非同帧直接投出)", belt7b.state == "working" and belt7b.progress < 1.0)

	_run(FRAMES_ONE_CELL)
	_check("7c 下游走满一格后投不出去 ⇒ blocked 且货不丢",
			belt7b.state == "blocked" and belt7b.bag.count == 1)
	_check("7d 整链守恒:源少 2 件(上游送完立刻又取了一件)、两条带各持 1 件",
			src7.bag.count == src7_before - 2 and belt7a.bag.count == 1 and belt7b.bag.count == 1)

	Level.current = null      # 静态指针不置空会留到退出,报一堆 ObjectDB 泄漏
	print("RESULT failed=", failed)
	quit(failed)
