extends Control
class_name BuildingCard

signal clicked()

func _ready():
	%model_renderer.position = Vector3.DOWN * 1000

func _on_panel_pressed() -> void:
	clicked.emit()
