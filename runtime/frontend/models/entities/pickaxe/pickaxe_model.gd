class_name PickaxeModel
extends Node3D

# 镐子物品模型(哑脚本):只作为 ItemStack 的道具池单元被实例化/测量/复用。
# ItemStack 只读取其 AABB 并等比缩放,本脚本不提供任何表现逻辑。
# 注意:美术源(models/tools/pickaxe/pickaxe.fbx)是直立握持姿态(长轴 +Y),本场景把实例
# 绕 X 转 −90° 放平,使其长轴落在 +Z —— 这是 ItemStack "长轴沿挂点 +Z" 的约定。
