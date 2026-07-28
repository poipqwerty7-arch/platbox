extends Node3D
## Корневой скрипт игрового мира.
## Если Session.pending_level_data задан (игрок зашёл в чью-то опубликованную игру),
## подменяет демо-геометрию на уровень, построенный из PlatLevel.
## Иначе оставляет дефолтный демо-мир как есть.

## Показывает "Тест" на экране, если игрок пришёл сюда через Test Play из
## редактора — небольшая визуальная подсказка, что это тестовый прогон, а не
## обычная игра из каталога.
func _ready() -> void:
	var back_button: Button = $HUD/BackButton
	back_button.pressed.connect(_on_back_pressed)
	if Session.is_test_play:
		back_button.text = "← Вернуться в редактор"

	var health_display = $HUD/HealthDisplay
	var player: CharacterBody3D = $Player
	health_display.connect_to_player(player)

	if Session.pending_level_data != null:
		_load_custom_level(Session.pending_level_data, player)
		Session.pending_level_data = null

func _load_custom_level(level_dict: Dictionary, player: CharacterBody3D) -> void:
	# Убираем демо-геометрию (Ground/Platform1-4) — вместо неё будет уровень игрока.
	for node in get_tree().get_nodes_in_group("demo_geometry"):
		node.queue_free()

	var level := PlatLevel.from_dict(level_dict)
	level.spawn_into($ObjectsRoot)

	player.global_position = level.get_spawn_position()
	player.spawn_position = level.get_spawn_position()

func _on_back_pressed() -> void:
	if OS.has_feature("mobile"):
		pass
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if Session.is_test_play:
		Session.is_test_play = false
		Session.editor_load_request = {"type": "test_return", "level_data": Session.editor_return_data}
		Session.editor_return_data = null
		get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/game_lobby.tscn")
