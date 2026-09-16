class_name Crossbow
extends Turret

# 弩炮:炮塔(Turret)的弩箭专用调参 —— 整条"值守/装填/蓄力/瞄准/发射"状态机、弹药仓、
# Fire 配方与发射几何都在 Turret 基类,本类只实现七个调参钩子给出弩箭的弹种/弹速/时序。
# 一次生产 = 本班值岗期间射出一发弩箭。满弦但未开火时工人继续值守(负责转身瞄准);
# 射出后工人离岗,基类按 _needs_worker() 自动补员。
# 无人值守时整塔停摆(不寻敌、不转向、不开火);有待发/蓄力中需求时才需要操作手。
#
# 区别于产出建筑:弩炮只有一只弹药输入仓(arrow,纯需求方),没有输出仓——产出的是一次
# 发射这一即时效果,而非可存放的物品。该"攻击"按瞬时效果机械形态声明为一张配方:
#   inputs = [arrow × 1], output = "", workload_per_unit = CHARGE_TIME(蓄满一发的蓄力)
# 配方用于 GUI 展示(消耗箭、耗时、进度)与 active_recipe 高亮;弹药仓仍作为展示镜像
# (前端据 stored_count/capacity 显示旁侧备箭)。蓄力/瞄准/开火时序由 Turret 状态机驱动。

const CHARGE_TIME: float = 3.0
const FIRE_TIME: float = 0.1
# 装填耗时:工人到位后先把一支弩矢从备箭垛端上弦(前端播上弦动画),随后才开始拉弦。
# 这段时间弦保持松弛(progress=0),属于"端箭准备",不占用蓄力工作量。
const LOAD_TIME: float = 0.6
# 弹药仓容量(纯需求方:低于上限即求补到满)
const AMMO_CAPACITY: int = 10
# 弩矢水平飞行速度(世界单位/秒)。与前端弹道(Trajectory 的重力抛物线)共用同一值:
# 飞行时长 T = 水平距离 / 本速度,故目标越远飞得越久、弧顶越高。弩身预览俯仰也用它。
const ARROW_SPEED: float = 10

# —— 弩箭调参:实现 Turret 的调参钩子 ——

func ammo_type() -> String:
	return "arrow"

func ammo_capacity() -> int:
	return AMMO_CAPACITY

func projectile_type() -> String:
	return "arrow"

func projectile_speed() -> float:
	return ARROW_SPEED

func charge_time() -> float:
	return CHARGE_TIME

func fire_time() -> float:
	return FIRE_TIME

func load_time() -> float:
	return LOAD_TIME
