class_name StoneMine
extends Workshop

# 石矿:工人注入 workload 开采石头(stone)入输出仓。产出连续,输出仓满即停。
# 配方经 recipes 声明(单配方:无输入 → stone),顺序 = 执行优先级;基类按配方输出建输出仓。
# 配方声明 required_tool = "pickaxe":工人会先去有镐子的容器取一把再开工(见 man_building.tres);
# 全图没有镐子时退化为空手工作(效率 0.1),有镐子则效率翻倍(见 Pickaxe)。

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
	recipe.required_tool = "pickaxe"
	return recipe
