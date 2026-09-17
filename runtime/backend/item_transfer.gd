class_name ItemTransfer
extends Node

# 一次"计时搬运":把若干件物品从源仓搬到目标仓,但不再是一瞬间完成 ——
#
#   开始  源仓 → 托管仓(escrow)   源侧立刻少掉("先扣")
#   过程  progress 0→1,由 Logistics.tick 推进
#   结束  托管仓 → 目标仓           目标侧到这一刻才多出来
#
# 为什么必须有托管仓:物品在"已离源、未达目标"的这段时间里得有个**真实归属**。Bag 是所属节点的
# 子节点、随主人一起释放(没有掉落),而有状态载体(工具)只在 add_state 时才 reparent —— 拿一个
# 载体引用当在途态,源仓一死那件就被连带销毁。放进一只挂在 Logistics 下的无限托管仓,既不随
# 源/目标仓死亡而销毁,又全程走 §5.8 唯一认可的搬运原语 move_to(有状态单体搬实例本身、耐久不重置)。
#
# 纯逻辑:不含位置/朝向 —— 表现层自己按 source_bag/dest_bag 解算世界锚点(见 RoomActor)。
# 本对象由 Logistics 创建并 tick,故工人换树/眩晕/死亡都不影响这趟搬运走完(见 logistics.gd)。

enum State { Running, Done, Cancelled }

# 一趟搬运的耗时(秒):固定值,与距离无关 —— 距离是表现层的事,这里只管"这趟要多久"。
const DURATION: float = 0.45
# 收尾兜底(秒):到点后若目标与源长期都收不下,退主基地后即收工,免得一条搬运永远占着在途账。
const SETTLE_TIMEOUT: float = 3.0

# 两端仓(由 begin 写入)。搬运期间可能被销毁,故一律先 is_instance_valid 再用。
var source_bag: Bag = null
var dest_bag: Bag = null
# 两端仓的 id:在 begin 时(两者都还有效)就抄下来,供 Logistics 事后按 id 比对 ——
# 直接读上面的引用可能读到已 freed 的实例。
var source_bag_id: int = 0
var dest_bag_id: int = 0
var item_type: String = ""
# 请求搬运的件数(实际以 moved 为准:源可能已被并发搬空而少给)
var amount: int = 0
# 在途件的真实归属(见类注释);本对象是它的父节点。
var escrow: Bag = null
var state: State = State.Running
# 已扣出源仓 / 已交付目标仓的件数;两者之差即此刻还在飞的件数。
var moved: int = 0
var delivered: int = 0

# 归一化进度 [0,1](§5.4 契约:数据层只出归一化值,到动画时间轴的换算一律在表现层)。
var progress: float = 0.0:
	get:
		return progress
	set(in_value):
		var clamped: float = clampf(in_value, 0.0, 1.0)
		if clamped == progress:
			return
		progress = clamped
		progress_changed.emit()

signal progress_changed()
# 终态广播(Running 之外只发一次):表现层据此收尾自毁,叶子据此结算。
signal finished(in_state: int)

var _elapsed: float = 0.0
var _settle_elapsed: float = 0.0

# 开一趟搬运并**立刻**把货扣进托管仓("先扣")。返回 false 表示源仓一件都没搬动(缺货/类型不符),
# 此时本对象不该被采用 —— 调用方直接按"什么都没取到"处理,不生成半成品搬运。
func begin(in_source: Bag, in_dest: Bag, in_item_type: String, in_amount: int) -> bool:
	if not is_instance_valid(in_source) or not is_instance_valid(in_dest):
		return false
	if in_item_type.is_empty() or in_amount <= 0:
		return false
	source_bag = in_source
	dest_bag = in_dest
	source_bag_id = in_source.id
	dest_bag_id = in_dest.id
	item_type = in_item_type
	amount = in_amount
	escrow = Bag.new()
	escrow.name = "Escrow"
	# 无限容量:托管仓只做中转,绝不能因为它"满了"而截断这趟搬运。
	escrow.max_count = Bag.UNLIMITED
	add_child(escrow)
	moved = source_bag.move_to(escrow, item_type, amount)
	return moved > 0

func tick(in_delta: float):
	if state != State.Running:
		return
	if progress < 1.0:
		_elapsed += in_delta
		progress = _elapsed / DURATION
		if progress < 1.0:
			return
	# 到点后每帧都试着把托管仓清空:目标仓可能正好这一帧才腾出位置。
	_settle_elapsed += in_delta
	_settle(false)

# 立刻收工并把在途件退回源侧(源仓失效则退目标/主基地)。仓被销毁、任务被取消、兜底超时都走这里 ——
# 任何时刻收工都不丢件。
func cancel():
	if state != State.Running:
		return
	_settle_elapsed = SETTLE_TIMEOUT
	_settle(true)

# 收尾:按 in_prefer_source 决定先给哪一端,收不下的再给另一端,再不行退主基地,三者都放不下就
# 留在托管仓里下帧再试(见 _finish 的失物仓说明)。正常到点先给目标;取消则先还源侧。
func _settle(in_prefer_source: bool):
	if not is_instance_valid(escrow):
		_finish(State.Done)
		return
	if not in_prefer_source and is_instance_valid(dest_bag):
		delivered += escrow.move_to(dest_bag, item_type, escrow.count_of(item_type))
	_move_rest_to(source_bag)
	if not in_prefer_source:
		_move_rest_to(dest_bag)
	if escrow.count_of(item_type) <= 0:
		_finish(State.Done)
		return
	_emergency_home()
	if escrow.count_of(item_type) <= 0:
		_finish(State.Done)
		return
	if _settle_elapsed >= SETTLE_TIMEOUT:
		_finish(State.Cancelled)

# 把托管仓里剩下的全给 in_bag(收不下的留在托管仓,由调用方继续兜)。
func _move_rest_to(in_bag: Bag):
	if not is_instance_valid(in_bag):
		return
	var pending: int = escrow.count_of(item_type)
	if pending <= 0:
		return
	escrow.move_to(in_bag, item_type, pending)

# 兜底归宿:主基地的展示仓(无限、通配,§5.8 的地图枢纽)。没有主基地 / 它已失效就什么都不做。
func _emergency_home():
	var main_base: MainBase = MainBase.current
	if not is_instance_valid(main_base):
		return
	var home: Bag = main_base.get_display_bag()
	if not is_instance_valid(home):
		return
	escrow.move_to(home, item_type, escrow.count_of(item_type))

func _finish(in_state: State):
	if state != State.Running:
		return
	state = in_state
	# 托管仓已空就释放,别留空节点;仍有件(目标/源/主基地全收不下)则把它过继给父节点 ——
	# 宁可留一只取不出来的"失物仓",也绝不销毁物品(§5.8)。该分支实际不可达(主基地仓无限通配)。
	if is_instance_valid(escrow):
		if escrow.count <= 0:
			escrow.queue_free()
		else:
			var host: Node = get_parent()
			if host:
				host.add_child(escrow)
		escrow = null
	finished.emit(state)
