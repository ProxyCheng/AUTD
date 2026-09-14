class_name CannonballModel
extends ArrowModel

# 炮弹表现模型:与弩箭共用同一套弹道表现(抛物线抬升 + 沿切线俯仰),故直接继承 ArrowModel
# —— 其 set_flight/set_state 由 EntityActor 按 has_method 探测调用,无需重写。
# 弹道公式本体仍在 backend(Arrow.arc_slope / Arrow.launch_pitch / Arrow.GRAVITY),前后端同源。
# 若日后炮弹需要独立表现(自转、拖尾、命中特效),在此覆写对应方法即可。
