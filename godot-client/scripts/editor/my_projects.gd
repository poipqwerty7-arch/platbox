extends Control
## Экран "Мои проекты": объединяет локальные черновики (user://drafts/) и
## опубликованные игры автора (с сервера) в один список, как во вкладке
## создания в Roblox Studio.

@onready var back_button: Button = $Margin/VBox/TopBar/BackButton
@onready var new_project_button: Button = $Margin/VBox/TopBar/NewProjectButton
@onready var projects_list: VBoxContainer = $Margin/VBox/ScrollContainer/ProjectsList

@onready var settings_dialog: Window = $SettingsDialog
@onready var name_input: LineEdit = $SettingsDialog/Margin/VBox/NameInput
@onready var color_input: ColorPickerButton = $SettingsDialog/Margin/VBox/ColorInput
@onready var save_settings_button: Button = $SettingsDialog/Margin/VBox/SaveButton
@onready var delete_button: Button = $SettingsDialog/Margin/VBox/DeleteButton
@onready var settings_status: Label = $SettingsDialog/Margin/VBox/StatusLabel

var editing_entry: Dictionary = {}  # текущий проект, открытый в диалоге настроек

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/game_lobby.tscn"))
	new_project_button.pressed.connect(_on_new_project)
	save_settings_button.pressed.connect(_on_save_settings)
	delete_button.pressed.connect(_on_delete_project)
	settings_dialog.close_requested.connect(func(): settings_dialog.hide())
	_refresh_list()

func _on_new_project() -> void:
	Session.editor_load_request = null
	get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")

func _refresh_list() -> void:
	for child in projects_list.get_children():
		child.queue_free()

	# Локальные черновики — сразу доступны, без сети.
	for draft in DraftStore.list_drafts():
		var level_dict: Dictionary = draft.get("level", {})
		projects_list.add_child(_build_card({
			"kind": "draft",
			"id": draft.get("draft_id", ""),
			"title": level_dict.get("title", "Без названия"),
			"thumbnail_color": level_dict.get("thumbnail_color", "#6c5ce7"),
			"status_text": "Черновик",
		}))

	# Опубликованные игры — подтягиваются с сервера асинхронно.
	if Session.is_logged_in():
		Session.fetch_my_games(func(games: Array):
			for game in games:
				projects_list.add_child(_build_card({
					"kind": "published",
					"id": str(game.get("id", "")),
					"title": game.get("title", "Без названия"),
					"thumbnail_color": game.get("thumbnail_color", "#6c5ce7"),
					"status_text": "Опубликовано",
				}))
		)

func _build_card(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	panel.add_child(hbox)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(48, 48)
	swatch.color = Color(entry["thumbnail_color"])
	hbox.add_child(swatch)

	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_box)

	var title_label := Label.new()
	title_label.text = entry["title"]
	title_label.add_theme_font_size_override("font_size", 16)
	info_box.add_child(title_label)

	var status_label := Label.new()
	status_label.text = entry["status_text"]
	status_label.modulate = Color(0.2, 0.85, 0.4) if entry["kind"] == "published" else Color(0.9, 0.7, 0.2)
	info_box.add_child(status_label)

	var open_button := Button.new()
	open_button.text = "Продолжить" if entry["kind"] == "draft" else "Открыть"
	open_button.pressed.connect(func(): _on_open(entry))
	hbox.add_child(open_button)

	var settings_button := Button.new()
	settings_button.text = "⚙ Настройки"
	settings_button.pressed.connect(func(): _open_settings(entry))
	hbox.add_child(settings_button)

	return panel

func _on_open(entry: Dictionary) -> void:
	if entry["kind"] == "draft":
		Session.editor_load_request = {"type": "draft", "draft_id": entry["id"]}
	else:
		Session.editor_load_request = {"type": "published", "game_id": entry["id"]}
	get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")

func _open_settings(entry: Dictionary) -> void:
	editing_entry = entry
	name_input.text = entry["title"]
	color_input.color = Color(entry["thumbnail_color"])
	settings_status.text = ""
	settings_dialog.popup_centered()

func _on_save_settings() -> void:
	var new_title := name_input.text.strip_edges()
	if new_title.is_empty():
		settings_status.text = "Название не может быть пустым"
		return
	var new_color := "#" + color_input.color.to_html(false)

	if editing_entry["kind"] == "draft":
		var level := DraftStore.load_draft_level(editing_entry["id"])
		if level:
			level.title = new_title
			level.thumbnail_color = new_color
			DraftStore.save_draft(level, editing_entry["id"])
		settings_dialog.hide()
		_refresh_list()
	else:
		save_settings_button.disabled = true
		Session.update_game_meta(editing_entry["id"], new_title, new_color, func(success: bool, message: String):
			save_settings_button.disabled = false
			if success:
				settings_dialog.hide()
				_refresh_list()
			else:
				settings_status.text = message
		)

func _on_delete_project() -> void:
	if editing_entry.get("kind", "") == "draft":
		DraftStore.delete_draft(editing_entry["id"])
		settings_dialog.hide()
		_refresh_list()
	else:
		# Удаление опубликованных игр — намеренно не делаем в этой версии:
		# это необратимо и заслуживает отдельного подтверждения ("точно-точно?").
		settings_status.text = "Удаление опубликованных игр появится позже"
