extends Control
## Лобби: показывает список игр, полученный с Platbox API, кликом запускает 3D-мир.

@onready var welcome_label: Label = $Margin/VBox/TopBar/WelcomeLabel
@onready var logout_button: Button = $Margin/VBox/TopBar/LogoutButton
@onready var games_grid: GridContainer = $Margin/VBox/ScrollContainer/GamesGrid

func _ready() -> void:
	if not Session.is_logged_in():
		get_tree().change_scene_to_file("res://scenes/login.tscn")
		return

	welcome_label.text = "Привет, %s! 🪙 %s" % [Session.user.get("display_name", "игрок"), Session.user.get("coins", 0)]
	logout_button.pressed.connect(_on_logout)
	Session.fetch_games(_on_games_loaded)

func _on_games_loaded(games: Array) -> void:
	for child in games_grid.get_children():
		child.queue_free()

	if games.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Игр пока нет."
		games_grid.add_child(empty_label)
		return

	for game in games:
		games_grid.add_child(_build_game_card(game))

func _build_game_card(game: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 160)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var thumb := ColorRect.new()
	thumb.custom_minimum_size = Vector2(0, 90)
	thumb.color = Color(game.get("thumbnail_color", "#6c5ce7"))
	vbox.add_child(thumb)

	var title := Label.new()
	title.text = game.get("title", "Без названия")
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var meta := Label.new()
	meta.text = "▶ %s игр" % str(game.get("play_count", 0))
	meta.modulate = Color(0.6, 0.6, 0.65)
	vbox.add_child(meta)

	var play_button := Button.new()
	play_button.text = "Играть"
	play_button.pressed.connect(func(): _on_play_pressed(game.get("id")))
	vbox.add_child(play_button)

	return panel

func _on_play_pressed(game_id) -> void:
	# Пока что все игры ведут в один и тот же демо-3D-мир.
	# По мере роста платформы game_id можно передавать в сцену мира,
	# чтобы подгружать разные уровни/сборки под каждую игру.
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _on_logout() -> void:
	Session.logout()
	get_tree().change_scene_to_file("res://scenes/login.tscn")
