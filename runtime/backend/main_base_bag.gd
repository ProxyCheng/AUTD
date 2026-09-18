class_name MainBaseBag
extends Bag

# 主基地的通配兜底仓:无限容量、接受任意类型,作为地图的"溢出缓冲区"。
#
# (i) 落库兜底:Logistics.find_nearest_bag 的落库分层(_deposit_rank)把通配仓判为最低层 ——
#     只要还有同类型的专仓收得下(料堆、作坊输入/产出仓…),货就进不来这里;这里只接"全图
#     没有专仓收得下"的溢出。deposit_priority = DEPOSIT_FIRST 只在同层(同为通配仓)内比较。
# (ii) 取用优先:withdraw_priority = WITHDRAW_FIRST —— 工人要工具时仍先来这里拿,先把溢出
#     缓冲用掉再动专仓。
# (iii) 通配(接受任意类型)+ 无限容量,且 preferred_min_count = 0 是承重墙:基地永不"欠货",
#      Logistics 绝不把它当需求方 —— 无限容量的仓一旦被当需求方,会把全图库存吸进自己嘴里。
# (iv) preferred_max_count = 0:只要基地有存货就始终处于"富余供给"态,成为合法供给源 ——
#      "有货即供给"。
# (v) preferred_max_count 的初值在 Bag 构造时绑定(= 当时的 max_count,bag.gd:54),
#      事后改 max_count 不会更新它,故 _init 里必须先设 max_count 再显式重设本值。
#
# 注意 (i) 与 (ii) 合起来是单向的:只要该类型存在收得下的专仓,基地里这类货就只出不进。
# 这是"专仓优先、基地兜底"的必然代价 —— 曾经的"双 FIRST 主动枢纽"(取它排第一、也还它排第一)
# 已废弃,见 AGENTS.md §5.8。

func _init():
	item_type = ""                        # 通配:接受任意类型
	accepts_any_type = true
	max_count = Bag.UNLIMITED             # 必须先于 preferred_max_count(见 (v))
	preferred_min_count = 0               # 永不作为 Logistics 需求方(承重墙,见 (ii))
	preferred_max_count = 0               # 有货即供给 → 恒为合法取货源
	withdraw_priority = Bag.WITHDRAW_FIRST   # 取用优先:工人要工具时先来这里拿
	deposit_priority  = Bag.DEPOSIT_FIRST    # 归还优先:用不上的工具回这里
