class_name Logistics
extends Node

# 物流调度中心:撮合"缺货请求方"与"富余供给方",生成搬运任务交 LaborManager 派劳工执行。
#
# bag 参与搬运的角色由 preferred_min/max 阈值声明(见 Bag):
#   count <  preferred_min_count → 缺货:希望被补货到 preferred_max_count。
#   count >  preferred_max_count → 富余:超出 preferred_max_count 的部分可外供。
#   纯请求方(只进不出):preferred_min = preferred_max = max_count(如 Crossbow 弹药箱)。
#   纯供给方(只出不进):preferred_min = preferred_max = 0(如 AUTO_FILL 的料堆,有货即出)。
#   仓储型:preferred_min 为自留警戒线(低于它求补),preferred_max 为外供起点(高于它才出)。
#
# 搬运量语义:每个劳工每趟最多携带 CARRY_CAPACITY 件(本类常量),因此一次缺货
# 会被拆成多个 TransportTask 依次派发。为避免重复投送,对每个目标 bag 维护
# inbound 预留(_inbound_reserved):已派发未送达的量计入,count+预留 达到
# preferred_max_count 即不再派;任务完成/取消时按承诺量释放预留并触发重估。
# 实际取/放都在搬运工到达装卸点时执行(Bag.remove_count/add_count 自带上下限截断),
# 因此即使源被并发搬空/目标被占满也不会出现负数或超容。

const CARRY_CAPACITY: int = 5
# 单帧最多新派发的搬运任务数(防批量缺货时一帧洪水式建任务)
const MAX_SPAWNS_PER_TICK: int = 4
# 一条搬运结束后仍留在登记表里的时长(秒):叶子是"下一 tick 才来问结果",必须留够;
# 留太久白占内存,故到期即释放。
const TRANSFER_LINGER: float = 5.0

# 搬运开始(源侧此刻就扣货,见 ItemTransfer)。表现层据此起一段飞行表现并跟着 progress 走。
signal transfer_started(transfer: ItemTransfer)

# { bag_id: Bag } 已注册 bag
var bags: Dictionary = {}
# { bag_id: true } 计数变化待重估的 bag
var changed_bags: Dictionary = {}
# { bag_id: 在途预留量 } 目标 bag 已派发未送达的件数
var _inbound_reserved: Dictionary = {}
# { TransportTask: { source_bag: Bag, dest_bag: Bag, amount: int } } 在途搬运任务
var _tasks: Dictionary = {}
# { bag_id: Callable } 注册时绑定的 count_changed 回调,供注销时断开
var _count_callbacks: Dictionary = {}
# 是否已连接 LaborManager 完成/取消信号(懒连接,Logistics 早于 LaborManager 入树)
var _signals_connected: bool = false
# { transfer_id: ItemTransfer } 在途 / 刚结束仍在保留期的搬运
var _transfers: Dictionary = {}
# { transfer_id: 剩余保留秒数 } 已终态但仍可被叶子查到的搬运
var _transfer_linger: Dictionary = {}
var _next_transfer_id: int = 1

func register_bag(in_bag: Bag):
	if bags.has(in_bag.id):
		return
	bags.set(in_bag.id, in_bag)
	var callback := func(): _on_bag_count_changed(in_bag.id)
	_count_callbacks.set(in_bag.id, callback)
	in_bag.count_changed.connect(callback)
	changed_bags.set(in_bag.id, true)

func unregister_bag(in_bag_id: int):
	# 先取消涉该 bag 的在途任务与在途搬运(可能同步触发 _on_task_finished),再清账本
	_cancel_tasks_for_bag(in_bag_id)
	_cancel_transfers_for_bag(in_bag_id)
	var bag: Bag = bags.get(in_bag_id)
	if bag:
		var callback: Callable = _count_callbacks.get(in_bag_id)
		if callback:
			bag.count_changed.disconnect(callback)
			_count_callbacks.erase(in_bag_id)
	bags.erase(in_bag_id)
	changed_bags.erase(in_bag_id)
	_inbound_reserved.erase(in_bag_id)

# 每帧:先推进在途搬运(与供需变化无关,故必须在下面的早退之前),再结算计数变化重估供需。
func tick(in_delta: float):
	_tick_transfers(in_delta)
	if changed_bags.is_empty():
		return
	var manager := _get_manager()
	if not manager:
		return
	_connect_signals(manager)
	changed_bags.clear()
	_schedule_transports()

# —— 计时搬运(ItemTransfer)——

# 开一趟计时搬运:逐件"取 → 飞 → 交"(见 ItemTransfer),这里负责登记与广播。
# 返回搬运 id 供叶子后续查询;源仓一件都没取到(缺货/类型不符)→ -1。
# 顺序要紧:**先广播 transfer_started,再取第一件** —— 表现层是在 transfer_started 里接上
# item_departed 的,反了的话第一件的起飞事件没人接,那件就白飞一趟。
func begin_transfer(in_source: Bag, in_dest: Bag, in_item_type: String, in_amount: int) -> int:
	var transfer := ItemTransfer.new()
	if not transfer.configure(in_source, in_dest, in_item_type, in_amount):
		transfer.free()
		return -1
	add_child(transfer)
	var transfer_id: int = _next_transfer_id
	_next_transfer_id += 1
	_transfers.set(transfer_id, transfer)
	transfer.finished.connect(_on_transfer_finished.bind(transfer_id))
	transfer_started.emit(transfer)
	if not transfer.take_first():
		# 一件都没取到:这趟不算数,撤掉登记(已广播的开始事件没有副作用:还没起飞过任何一件)。
		_transfers.erase(transfer_id)
		transfer.queue_free()
		return -1
	return transfer_id

# 按 id 取搬运:在途的、以及已终态但仍在保留期内的都能取到(叶子下一 tick 才来问结果);
# 保留期过后彻底释放,返回 null —— 叶子据此把"查不到"当失败处理。
func get_transfer(in_transfer_id: int) -> ItemTransfer:
	var transfer: ItemTransfer = _transfers.get(in_transfer_id)
	return transfer

func _on_transfer_finished(_in_state: int, in_transfer_id: int):
	_transfer_linger.set(in_transfer_id, TRANSFER_LINGER)

func _tick_transfers(in_delta: float):
	# keys() 返回副本,故循环里 erase 安全。
	for transfer_id: int in _transfers.keys():
		var transfer: ItemTransfer = _transfers.get(transfer_id)
		if not is_instance_valid(transfer):
			_transfers.erase(transfer_id)
			_transfer_linger.erase(transfer_id)
			continue
		transfer.tick(in_delta)
		if not _transfer_linger.has(transfer_id):
			continue
		var left: float = float(_transfer_linger.get(transfer_id)) - in_delta
		if left > 0.0:
			_transfer_linger.set(transfer_id, left)
			continue
		_transfer_linger.erase(transfer_id)
		_transfers.erase(transfer_id)
		transfer.queue_free()

# 把涉某仓的在途搬运全部立刻结算掉(见 ItemTransfer.cancel)。供"这件活到此为止"的场景调用
# (工人换任务、仓被销毁)。货退回仍收得下的那一端,绝不丢件。
func cancel_transfers_for(in_bag: Bag):
	if is_instance_valid(in_bag):
		_cancel_transfers_for_bag(in_bag.id)

# 有仓被销毁 → 涉它的在途搬运立刻收工并把货退还(见 ItemTransfer.cancel)。
# 按 begin 时抄下的 bag id 比对,不去读可能已 freed 的引用。
func _cancel_transfers_for_bag(in_bag_id: int):
	for transfer_id: int in _transfers.keys():
		var transfer: ItemTransfer = _transfers.get(transfer_id)
		if not is_instance_valid(transfer) or transfer.state != ItemTransfer.State.Running:
			continue
		if transfer.source_bag_id == in_bag_id or transfer.dest_bag_id == in_bag_id:
			transfer.cancel()

func _on_bag_count_changed(in_bag_id: int):
	if not bags.has(in_bag_id):
		return  # 已注销的 bag 的游离回调,忽略
	changed_bags.set(in_bag_id, true)

# —— 供需匹配 ——

func _schedule_transports():
	# 先收集全部缺货需求,再按补货优先级降序排:高优先级建筑的需求先占用本帧有限的
	# 派发名额(MAX_SPAWNS_PER_TICK)。同优先级按 bag.id 升序 —— id 按注册顺序发放,
	# 故同档位仍是今天的 FIFO 行为,不改变既有调度公平性。
	# 只排需求侧:源仓仍由 _find_source 按"离请求方最近"挑,不受影响。
	var demands: Array[Bag] = []
	for bag: Bag in bags.values():
		if bag.is_understocked():
			demands.append(bag)
	demands.sort_custom(func(in_a: Bag, in_b: Bag) -> bool:
		if in_a.transport_priority != in_b.transport_priority:
			return in_a.transport_priority > in_b.transport_priority
		return in_a.id < in_b.id)
	var spawned: int = 0
	for demand_entry: Bag in demands:
		if spawned >= MAX_SPAWNS_PER_TICK:
			break
		var available: int = demand_entry.preferred_max_count - demand_entry.count \
				- int(_inbound_reserved.get(demand_entry.id, 0))
		if available <= 0:
			continue
		var source := _find_source(demand_entry)
		if not source:
			continue
		var amount: int = mini(available, source.surplus_of(demand_entry.item_type))
		amount = mini(amount, CARRY_CAPACITY)
		if amount <= 0:
			continue
		_spawn_transport(source, demand_entry, amount)
		spawned += 1

# 最近的"可收/可取的仓":只读,不改任何账本。
# in_need_stock = true 取有货的(本仓该类型 count_of > 0,供领工具);false 取收得下的(未满,供还/卸货)。
# 类型匹配:bag.accepts_any_type 为真则跳过类型比对(通配仓),否则要求 item_type 相同。
# 排序(放货 in_need_stock = false):先比落库分层 _deposit_rank(同类型仓 > 通配兜底仓),
#   同层再比 deposit_priority(高者胜),最后比距离(近者胜)。
# 排序(取货 in_need_stock = true):先比 withdraw_priority(高者胜),同档再比距离(近者胜)。
# 供顶岗取/还工具(ManBuildingTask)、空闲卸货(FindDepositBagTask)、开工前归还(PlanReturnTask)共用,
# 是"就近挑仓"的唯一实现。
func find_nearest_bag(in_item_type: String, in_from: Vector2, in_need_stock: bool) -> Bag:
	var best: Bag = null
	var best_rank: int = 0
	var best_priority: int = 0
	var best_distance: float = INF
	for bag: Bag in bags.values():
		if not bag.accepts_any_type and bag.item_type != in_item_type:
			continue
		if in_need_stock and bag.count_of(in_item_type) <= 0:
			continue
		if not in_need_stock and bag.is_full():
			continue
		var rank: int = 0 if in_need_stock else _deposit_rank(bag, in_item_type)
		var priority: int = bag.withdraw_priority if in_need_stock else bag.deposit_priority
		var distance: float = bag.access_position.distance_to(in_from)
		# best == null 兜首只候选:偏好可以为负(DEPOSIT_LAST),不能用 best_priority 的初值把它挡掉。
		if best == null or rank > best_rank \
				or (rank == best_rank and priority > best_priority) \
				or (rank == best_rank and priority == best_priority and distance < best_distance):
			best = bag
			best_rank = rank
			best_priority = priority
			best_distance = distance
	return best

# 落库分层(只用于"找收得下的仓",即 in_need_stock = false):越"专"的仓越优先 ——
#   2 = 同类型仓,且 count_of 未到 preferred_max_count(该仓自己声明"我还想装到这么多");
#   1 = 同类型仓,且未满(物理上收得下);
#   0 = 其余(通配仓,如 MainBaseBag —— 只作最后兜底)。
# "同类型" = bag.item_type == 目标类型;通配仓(accepts_any_type)不算同类型,故恒为 0,
# 于是主基地排在所有同类型仓之后。分层压过 deposit_priority:档位只在同层内比较,
# 避免兜底仓凭档位抢走本该进专仓的货(工具坊的产出仓 preferred_max = 0,故属第 1 层)。
func _deposit_rank(in_bag: Bag, in_item_type: String) -> int:
	if in_bag.accepts_any_type:
		return 0
	if in_bag.count_of(in_item_type) < in_bag.preferred_max_count:
		return 2
	return 1

# 选供给方:类型匹配同 find_nearest_bag(通配仓跳过类型比对),且本仓该类型有富余(surplus_of > 0)。
# 排序:withdraw_priority 降序(高者优先被取货),同档比到请求方装卸点的距离(近者胜);
# 既有 bag 的 withdraw_priority 皆 0,故退化为纯就近,与引入偏好前完全一致。
func _find_source(in_demand: Bag) -> Bag:
	var best: Bag = null
	var best_priority: int = 0
	var best_distance: float = INF
	for candidate: Bag in bags.values():
		if candidate == in_demand:
			continue
		if not candidate.accepts_any_type and candidate.item_type != in_demand.item_type:
			continue
		if candidate.surplus_of(in_demand.item_type) <= 0:
			continue
		var distance: float = candidate.access_position.distance_to(in_demand.access_position)
		if best == null or candidate.withdraw_priority > best_priority \
				or (candidate.withdraw_priority == best_priority and distance < best_distance):
			best = candidate
			best_priority = candidate.withdraw_priority
			best_distance = distance
	return best

func _spawn_transport(in_source: Bag, in_dest: Bag, in_amount: int):
	var manager := _get_manager()
	if not manager:
		return
	# 搬运类型取请求方声明的那一类:通配仓的 item_type 为空,类型必须由需求侧显式给出,
	# 否则 move_to 会因空类型一件都搬不动却报成功(见 TransportTask.item_type)。
	var task := TransportTask.new(in_source, in_dest, in_amount, in_dest.item_type)
	manager.register_task(task)
	_inbound_reserved.set(in_dest.id, int(_inbound_reserved.get(in_dest.id, 0)) + in_amount)
	_tasks.set(task, { "source_bag": in_source, "dest_bag": in_dest, "amount": in_amount })

# —— 任务收尾:完成/取消都释放目标预留,并重估相关 bag(取消可能未触发计数变化) ——

func _on_task_finished(in_task: LaborTask):
	if not _tasks.has(in_task):
		return  # 非本调度生成的搬运任务(如顶岗任务)忽略
	var info: Dictionary = _tasks.get(in_task)
	_tasks.erase(in_task)
	# 先把字典里的 bag 取出为无类型临时变量,再 is_instance_valid 判定后才赋给 typed 变量。
	# 若先 `var x: Bag = info.get(...)`,赋值瞬间遇上已 queue_free 的 bag 就会抛
	# "Trying to assign invalid previously freed instance"(赋值本身即崩,is_instance_valid 赶不上)。
	var raw_dest: Variant = info.get("dest_bag")
	# is_instance_valid 对已 freed 的 Variant 是安全的(返回 false);先判它,true 才敢用 `is`
	# (freed 对象上做 `is` 也会崩)。故顺序必须是 is_instance_valid → is。
	if is_instance_valid(raw_dest) and raw_dest is Bag and bags.has(raw_dest.id):
		var reserved: int = int(_inbound_reserved.get(raw_dest.id, 0))
		_inbound_reserved.set(raw_dest.id, maxi(0, reserved - int(info.get("amount"))))
		changed_bags.set(raw_dest.id, true)
	# 任务结束必然动了源 bag(取货)或目标 bag(放货);标记源侧以备再估
	var raw_source: Variant = info.get("source_bag")
	if is_instance_valid(raw_source) and raw_source is Bag and bags.has(raw_source.id):
		changed_bags.set(raw_source.id, true)

func _cancel_tasks_for_bag(in_bag_id: int):
	var manager := _get_manager()
	if not manager:
		return
	var doomed: Array = []
	for task: TransportTask in _tasks.keys():
		var info: Dictionary = _tasks.get(task)
		# 用无类型临时变量,Avoid 赋值瞬间遇上已 freed 的 bag(typed 赋值即崩)
		var raw_source: Variant = info.get("source_bag")
		var raw_dest: Variant = info.get("dest_bag")
		# 顺序:is_instance_valid(对 freed 安全)→ 才 `is`;freed 上做 `is` 会崩。
		var src_id: int = raw_source.id if (is_instance_valid(raw_source) and raw_source is Bag) else -1
		var dst_id: int = raw_dest.id if (is_instance_valid(raw_dest) and raw_dest is Bag) else -1
		if src_id == in_bag_id or dst_id == in_bag_id:
			doomed.append(task)
	for task: TransportTask in doomed:
		if is_instance_valid(task) and not task.is_cancelled:
			manager.cancel_task(task)

func _connect_signals(in_manager: LaborManager):
	if _signals_connected:
		return
	in_manager.task_completed.connect(_on_task_finished)
	in_manager.task_cancelled.connect(_on_task_finished)
	_signals_connected = true

func _get_manager() -> LaborManager:
	if not Level.current:
		return null
	return Level.current.labor_manager
