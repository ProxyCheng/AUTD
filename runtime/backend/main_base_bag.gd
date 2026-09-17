class_name MainBaseBag
extends Bag

# 主基地的主动枢纽仓:地图的中央仓库 —— 工人要工具时优先从这里取,用不上的工具优先还回这里,
# 于是它的库存随劳动节奏可见地涨落;而不是只在"别的仓全满/全空"时才挪动的被动蓄水池。
# 枢纽地位完全由下面这些声明属性在 Logistics 撮合中自然涌现,不写任何特判。
#
# (i) 主动枢纽:入库/出库都排第一(双 FIRST),工人取工具先来这里拿、用不上的工具也先还回这里。
# (ii) 通配(接受任意类型)+ 无限容量,且 preferred_min_count = 0 是承重墙:基地永不"欠货",
#      Logistics 绝不把它当需求方 —— 无限容量的仓一旦被当需求方,会把全图库存吸进自己嘴里。
# (iii) preferred_max_count = 0:只要基地有存货就始终处于"富余供给"态,成为合法供给源 ——
#      "有货即供给"。
# (iv) 两条优先级轴必须同档(FIRST 配 FIRST / LAST 配 LAST):混搭会组成单向流 ——
#      取它排第一、还它排最后 ⇒ 只出不进,实测就是这样把基地抽干的(旧 bug);反向混搭则只进不出。
#      故本仓要么双 LAST(被动蓄水池),要么双 FIRST(主动枢纽),当前取双 FIRST。
# (v) preferred_max_count 的初值在 Bag 构造时绑定(= 当时的 max_count,bag.gd:54),
#      事后改 max_count 不会更新它,故 _init 里必须先设 max_count 再显式重设本值。

func _init():
	item_type = ""                        # 通配:接受任意类型
	accepts_any_type = true
	max_count = Bag.UNLIMITED             # 必须先于 preferred_max_count(见 (v))
	preferred_min_count = 0               # 永不作为 Logistics 需求方(承重墙,见 (ii))
	preferred_max_count = 0               # 有货即供给 → 恒为合法取货源
	withdraw_priority = Bag.WITHDRAW_FIRST   # 取用优先:工人要工具时先来这里拿
	deposit_priority  = Bag.DEPOSIT_FIRST    # 归还优先:用不上的工具回这里
