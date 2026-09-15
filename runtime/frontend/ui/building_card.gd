extends Control
class_name BuildingCard

signal clicked()

@onready var _panel: Button = $Panel

func _ready():
	# 触屏无悬停:跳过 hover 音,避免点击时先响一声 hover 再响 click。
	if DisplayServer.is_touchscreen_available():
		return
	_panel.mouse_entered.connect(_on_panel_hover)

# 悬停提示音:压到 SFX 基准音量之下,避免鼠标划过卡片时喧宾夺主。
func _on_panel_hover():
	AudioManager.sfx(&"ui_hover", 1.0, -8.0)

func _on_panel_pressed():
	AudioManager.sfx(&"ui_click")
	clicked.emit()
