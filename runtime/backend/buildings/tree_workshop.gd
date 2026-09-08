class_name TreeWorkshop
extends ProducerWorkshop

# 伐木场:工人注入 workload 采伐原木(log)入输出仓。产出连续,输出仓满即停。
# 只需覆写 _produces() 声明输出物类型;无输入要求(天然资源,不消耗)。

# 产出一件原木所需的累计工作量(秒)。伐木略慢于石矿,鼓励按需布置。
func _ready():
	workload_per_unit = 2.5
	super._ready()

func _produces() -> String:
	return "log"
