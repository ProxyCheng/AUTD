class_name TreeWorkshop
extends Workshop

# 伐木场:工人注入 workload 采伐原木(log)入输出仓。产出连续,输出仓满即停。
# 配方经 recipes 声明(单配方:无输入 → log),顺序 = 执行优先级;基类按配方输出建输出仓。

# 产出一件原木所需的累计工作量(秒)。伐木略慢于石矿,鼓励按需布置。
const LOG_WORKLOAD: float = 2.5

func _ready():
	recipes = [_make_log_recipe()]
	super._ready()

func _make_log_recipe() -> RecipeData:
	var recipe := RecipeData.new()
	recipe.label = "Log"
	recipe.output = "log"
	recipe.workload_per_unit = LOG_WORKLOAD
	return recipe
