extends Control
class_name BuildingCard

signal clicked()

func _on_panel_pressed() -> void:
	clicked.emit()
