extends Control
class_name BuildingCard

signal clicked()

@onready var _panel: Button = $Panel

func _ready():
	_panel.mouse_entered.connect(_on_panel_hover)

# 悬停提示音:压到 SFX 基准音量之下,避免鼠标划过卡片时喧宾夺主。
func _on_panel_hover():
	AudioManager.sfx(&"ui_hover", 1.0, -8.0)

func _on_panel_pressed():
	AudioManager.sfx(&"ui_click")
	clicked.emit()
