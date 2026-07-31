class_name ActionStatus

const SUCCESS: int = 0
const FAILURE: int = 1
const RUNNING: int = 2

var type: int = SUCCESS
var remained_time: float = 0

static func success(in_remained_time: float) -> ActionStatus:
	return ActionStatus.new(SUCCESS, in_remained_time)

static func failure(in_remained_time: float) -> ActionStatus:
	return ActionStatus.new(FAILURE, in_remained_time)

static func running(in_remained_time: float = 0) -> ActionStatus:
	return ActionStatus.new(RUNNING, in_remained_time)

func is_success() -> bool:
	return type == SUCCESS

func is_failure() -> bool:
	return type == FAILURE

func is_running() -> bool:
	return type == RUNNING

func _init(in_type: int, in_remained_time: float = 0):
	type = in_type
	remained_time = in_remained_time
