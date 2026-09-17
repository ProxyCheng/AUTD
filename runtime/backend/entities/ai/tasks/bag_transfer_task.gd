class_name BagTransferTask
extends BTAction

# 走"计时搬运"(ItemTransfer)的叶子基类:把"开一趟搬运 → 等它飞完 → 结算"这段每个取/放叶子
# 都要写一遍的状态机收在这里(见 AGENTS §5.3:叶子只留自己的业务判据)。
#
# 为什么叶子必须跨 tick 等待:搬运不再是瞬间完成 —— 开趟当帧源仓就扣货、货进了托管仓飞着,
# 到点才交给目标仓(见 ItemTransfer)。叶子这一 tick 只拿得到"在途",要等它落地才知道
# 到底搬成了几件,故必须返回 RUNNING。
#
# 叶子用法:
#   _tick 里解析出两端仓与件数 → begin_transfer(...);返回 true 就 return RUNNING;
#   之后每 tick 先 await_transfer(),拿到终态再读 delivered()/moved() 做结算。
# 注意:搬运对象归 Logistics 所有,**不随树一起消失** —— 叶子被换掉/工人眩晕/死亡都不影响
# 这趟走完(这也是不能把在途件挂在叶子上的原因:叶子的 _exit 不保证被调用)。

var _transfer_id: int = -1

# 叶子可能被重复进入(BTRepeat 会重跑同一个克隆体),故每次进入都要从"未开始"起算;
# 但上一趟若还在飞就**不能**重开 —— 那会把它丢下又开一趟,等于同一批货搬两遍。
func _enter():
	if _transfer_id < 0:
		return
	var transfer: ItemTransfer = _transfer()
	if transfer == null or transfer.state != ItemTransfer.State.Running:
		_transfer_id = -1

# 开一趟计时搬运:源仓此刻就扣货进托管仓。返回 true = 已开成,本 tick 应 return RUNNING。
# 返回 false = 一件都没搬动(源仓缺货/类型不符/参数不合法),由调用方按自己的语义处理
# (取货是 FAILURE;空闲卸货是 SUCCESS)。
func begin_transfer(in_source: Bag, in_dest: Bag, in_item_type: String, in_amount: int) -> bool:
	var logistics: Logistics = Level.current.logistics if Level.current else null
	if logistics == null:
		return false
	_transfer_id = logistics.begin_transfer(in_source, in_dest, in_item_type, in_amount)
	return _transfer_id >= 0

# 等本趟落地:在途 → RUNNING;搬完 → SUCCESS;被取消 / 查不到(保留期已过)→ FAILURE。
func await_transfer() -> int:
	var transfer: ItemTransfer = _transfer()
	if transfer == null:
		return BT.Status.FAILURE
	if transfer.state == ItemTransfer.State.Running:
		return BT.Status.RUNNING
	return BT.Status.SUCCESS if transfer.state == ItemTransfer.State.Done else BT.Status.FAILURE

# 本趟已交付目标仓的件数;未开始 / 查不到 → 0。
func delivered() -> int:
	var transfer: ItemTransfer = _transfer()
	return transfer.delivered if transfer else 0

# 本趟已扣出源仓的件数;未开始 / 查不到 → 0。
func moved() -> int:
	var transfer: ItemTransfer = _transfer()
	return transfer.moved if transfer else 0

# 本趟的物品类型:以开趟那一刻为准(黑板可能已被后续步骤改写);未开始 → ""。
func transfer_type() -> String:
	var transfer: ItemTransfer = _transfer()
	return transfer.item_type if transfer else ""

func _transfer() -> ItemTransfer:
	if _transfer_id < 0:
		return null
	var logistics: Logistics = Level.current.logistics if Level.current else null
	return logistics.get_transfer(_transfer_id) if logistics else null
