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

# 单件物品的飞行时长(秒):一趟搬 N 件的总时长 = N × 本值。
# 逐件飞,不整批一次飞 —— 进度被等分成 N 段,第 i 件在进度 i/N 处落地(见 _release_due),
# 表现层按同一把尺子把 N 件排成一串(见 ItemFlight),于是"目标区域多出来"与"那件飞到"同拍。
const PER_ITEM_DURATION: float = 0.25
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
# 已扣出源仓 / 已交付目标仓的件数。逐件循环(见 _advance),故两者之差恒为 0 或 1 ——
# 同一时刻至多一件在飞,源仓与目标仓各只动一件,在途暴露面就是这一件。
var moved: int = 0
var delivered: int = 0
# 本趟总时长(秒):按实际搬走的件数算(见 PER_ITEM_DURATION),故一件一件都看得清。
var duration: float = PER_ITEM_DURATION

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
# 第 in_index 件**刚被取出源仓**(进入托管仓)时广播:表现层据此起这一段飞行。
# 逐件广播而不是开场一次广播 N 件 —— 源仓可能被并发搬空而少给,开场就摆 N 段飞行会飞出并不存在的货。
signal item_departed(in_index: int)
# 终态广播(Running 之外只发一次):表现层据此收尾自毁,叶子据此结算。
signal finished(in_state: int)

var _elapsed: float = 0.0
var _settle_elapsed: float = 0.0

# 配置两端与件数(此时**不取货**)。取货交给 take_first —— 调用方得先把"搬运开始"广播出去,
# 表现层才来得及接上 item_departed(见 Logistics.begin_transfer);顺序反了第一件就没人接、白飞一趟。
func configure(in_source: Bag, in_dest: Bag, in_item_type: String, in_amount: int) -> bool:
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
	# 总时长随件数走:每件各占一段进度,故件件都看得清(表现层把 N 件按同一把尺子排成一串)。
	duration = maxf(PER_ITEM_DURATION, float(amount) * PER_ITEM_DURATION)
	return true

# 取第一件("先扣"从这一件开始,见 _advance)。返回 false = 源仓一件都没取到(缺货/类型不符),
# 此时本对象不成立,调用方应直接丢弃、按"什么都没取到"处理。
func take_first() -> bool:
	return _take_one()

func tick(in_delta: float):
	if state != State.Running:
		return
	if progress < 1.0:
		_elapsed += in_delta
		progress = _elapsed / duration
		_advance()
		if progress < 1.0:
			return
# 到点后每帧都试着把托管仓清空:目标仓可能正好这一帧才腾出位置。
	_settle_elapsed += in_delta
	_settle(false, State.Done)

# 立刻收工并把在途件退回源侧(源仓失效则退目标/主基地)。仓被销毁、任务被取消、工人换活都走这里 ——
# 任何时刻收工都不丢件。终态记 Cancelled:即便货全退回来了,这趟也**没搬成**,
# 叶子据此判 FAILURE(见 BagTransferTask.await_transfer),不会把"什么都没搬"当成功。
func cancel():
	if state != State.Running:
		return
	_settle_elapsed = SETTLE_TIMEOUT
	_settle(true, State.Cancelled)

# 按进度推进"逐件"循环:到第 i 件的起跑点就从源仓取它(源 → 托管仓),到它的终点就交付(托管仓 → 目标)。
# 于是同一时刻源仓只少一件、目标仓只多一件 —— 飞行与两端库存始终同拍,
# 而不是"整批一次扣完、再一件件补进目标"(那样源仓会先闪空,看着像凭空消失)。
func _advance():
	var flying: int = mini(int(floor(progress * float(amount))), amount)
	# 先交该交的(第 0..flying-1 件),再保证当前这件已经取出来(第 flying 件)。
	while delivered < flying:
		if not _deliver_one():
			break
	while moved <= flying and moved < amount:
		if not _take_one():
			break

# 取下一件进托管仓(先扣);源仓被并发搬空 → 返回 false,本批到此为止。
# 取到的瞬间广播 item_departed:表现层据此起这一段飞行(逐件起,故不会飞出并不存在的货)。
func _take_one() -> bool:
	if not is_instance_valid(source_bag) or not is_instance_valid(escrow):
		return false
	if source_bag.move_to(escrow, item_type, 1) <= 0:
		return false
	item_departed.emit(moved)
	moved += 1
	return true

# 把托管仓里那件交给目标仓;目标仓收不下 → 返回 false(余下由到点后的 _settle 兜底)。
func _deliver_one() -> bool:
	if not is_instance_valid(escrow) or not is_instance_valid(dest_bag):
		return false
	if escrow.move_to(dest_bag, item_type, 1) <= 0:
		return false
	delivered += 1
	return true

# 收尾:按 in_prefer_source 决定先给哪一端,收不下的再给另一端,再不行退主基地,三者都放不下就
# 留在托管仓里下帧再试(见 _finish 的失物仓说明)。正常到点先给目标;取消则先还源侧。
# 货安置好即收工,终态用 in_terminal —— "退回来了"与"搬成了"是两件事,不能都记 Done。
func _settle(in_prefer_source: bool, in_terminal: State):
	if not is_instance_valid(escrow):
		_finish(in_terminal)
		return
	if not in_prefer_source and is_instance_valid(dest_bag):
		delivered += escrow.move_to(dest_bag, item_type, escrow.count_of(item_type))
	_move_rest_to(source_bag)
	if not in_prefer_source:
		_move_rest_to(dest_bag)
	if escrow.count_of(item_type) <= 0:
		_finish(in_terminal)
		return
	_emergency_home()
	if escrow.count_of(item_type) <= 0:
		_finish(in_terminal)
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
