class_name StoneMine
extends Workshop

# 石矿:工人注入 workload 开采石头(stone)入输出仓。产出连续,输出仓满即停。
# 配方经 recipes 声明(单配方:无输入 → stone),顺序 = 执行优先级;基类按配方输出建输出仓。
# 配方的 tool_bonuses 声明 { "pickaxe": 2.0 }:工人会先去有镐子的容器取一把再开工(见 man_building.tres);
# 全图没有镐子时按基准 1.0 工作(工具是纯增益,不是硬需求),持镐则注入量翻倍。

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
	recipe.tool_bonuses = {"pickaxe": 2.0}
	return recipe
