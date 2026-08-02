class_name Damage

const PHYSICAL: int = 0
const MAGICAL: int = 1

var type: int = PHYSICAL
var amount: float = 10

static func physical(in_amount: float):
	return Damage.new(PHYSICAL, in_amount)

static func magical(in_amount: float):
	return Damage.new(MAGICAL, in_amount)

func _init(in_type: int, in_amount: float):
	type = in_type
	amount = in_amount
