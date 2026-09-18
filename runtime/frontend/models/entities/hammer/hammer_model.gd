class_name HammerModel
extends Node3D

# 锤子的道具模型(哑表现):只被 ItemStack 实例化/测量/复用。
# ItemStack 只读其 AABB 并等比缩放,不依赖任何表现接口。
# 注释:美术源(models/tools/hammer/hammer.fbx)是直立握持姿态(长轴 +Y),在场景里实例
# 绕 X 轴转 90° 放平,使其长轴落在 +Z —— 这是 ItemStack "长轴沿挂点 +Z" 的约定。
