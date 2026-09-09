class_name StoneMine
extends Workshop

# 石矿:工人注入 workload 开采石头(stone)入输出仓。产出连续,输出仓满即停。
# 配方经 recipes 声明(单配方:无输入 → stone),顺序 = 执行优先级;基类按配方输出建输出仓。

# 产出一件石头所需的累计工作量(秒)。略快于伐木。
const STONE_WORKLOAD: float = 2.0

func _ready():
	recipes = [_make_stone_recipe()]
	super._ready()

func _make_stone_recipe() -> RecipeData:
	var recipe := RecipeData.new()
	recipe.label = "Stone"
	recipe.output = "stone"
	recipe.workload_per_unit = STONE_WORKLOAD
	return recipe
