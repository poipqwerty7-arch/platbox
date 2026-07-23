extends Node3D
## Корневой скрипт игрового мира: пока отвечает только за кнопку "Назад в лобби".

func _ready() -> void:
	var back_button: Button = $HUD/BackButton
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	if OS.has_feature("mobile"):
		pass
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/game_lobby.tscn")
