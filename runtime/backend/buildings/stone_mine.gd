class_name StoneMine
extends Workshop

# 石矿:工人注入 workload 开采石头(stone)入输出仓。产出连续,输出仓满即停。
# 只需覆写 _produces() 声明输出物类型;无输入要求(天然资源,不消耗)。

# 产出一件石头所需的累计工作量(秒)。略快于伐木。
func _ready():
	workload_per_unit = 2.0
	super._ready()

func _produces() -> String:
	return "stone"
