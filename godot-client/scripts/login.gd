extends Control
## Экран авторизации: логин + регистрация в одном поле формы.
## Долгое нажатие / второй клик по "Создать аккаунт" переключает режим.

@onready var identifier_input: LineEdit = $CenterContainer/Panel/Margin/VBox/IdentifierInput
@onready var password_input: LineEdit = $CenterContainer/Panel/Margin/VBox/PasswordInput
@onready var login_button: Button = $CenterContainer/Panel/Margin/VBox/LoginButton
@onready var register_button: Button = $CenterContainer/Panel/Margin/VBox/RegisterButton
@onready var error_label: Label = $CenterContainer/Panel/Margin/VBox/ErrorLabel
@onready var subtitle: Label = $CenterContainer/Panel/Margin/VBox/Subtitle

var register_mode := false
var email_input: LineEdit  # создаётся динамически при переключении в режим регистрации

func _ready() -> void:
	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_register_toggle)
	Session.login_success.connect(_on_login_success)
	Session.login_failed.connect(_on_auth_failed)
	Session.register_success.connect(_on_login_success)
	Session.register_failed.connect(_on_auth_failed)

func _on_register_toggle() -> void:
	register_mode = not register_mode
	if register_mode:
		subtitle.text = "Создай аккаунт Platbox"
		login_button.text = "Зарегистрироваться"
		register_button.text = "У меня уже есть аккаунт"
		if email_input == null:
			email_input = LineEdit.new()
			email_input.placeholder_text = "Email"
			var vbox := $CenterContainer/Panel/Margin/VBox
			vbox.add_child(email_input)
			vbox.move_child(email_input, password_input.get_index())
	else:
		subtitle.text = "Войди, чтобы играть"
		login_button.text = "Войти"
		register_button.text = "Создать аккаунт"
		if email_input:
			email_input.queue_free()
			email_input = null

func _on_login_pressed() -> void:
	error_label.visible = false
	var identifier := identifier_input.text.strip_edges()
	var password := password_input.text

	if identifier.is_empty() or password.is_empty():
		_show_error("Заполни все поля")
		return

	login_button.disabled = true

	if register_mode:
		var email := email_input.text.strip_edges() if email_input else ""
		if email.is_empty():
			_show_error("Введи email")
			login_button.disabled = false
			return
		Session.register(identifier, email, password)
	else:
		Session.login(identifier, password)

func _on_login_success(_user: Dictionary) -> void:
	login_button.disabled = false
	get_tree().change_scene_to_file("res://scenes/game_lobby.tscn")

func _on_auth_failed(message: String) -> void:
	login_button.disabled = false
	_show_error(message)

func _show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = true
