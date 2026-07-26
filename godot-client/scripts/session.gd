extends Node
## Session — глобальный синглтон (autoload).
## Хранит токен авторизации и данные игрока, общается с Platbox API.

# Публичный адрес бэкенда на Railway. Замени "твой-проект" на реальный поддомен
# после деплоя (Railway → Settings → Networking → Generate Domain).
const RAILWAY_URL := "https://platbox-production-0c97.up.railway.app/api"

# Для локальной разработки на ПК: http://127.0.0.1:3000/api
# Для Android-эмулятора с локальным сервером: http://10.0.2.2:3000/api
const LOCAL_URL := "http://127.0.0.1:3000/api"

# Переключатель: true — всегда бить в Railway, false — в локальный сервер.
# Удобно на время разработки поставить false, а перед сборкой релиза — true.
const USE_REMOTE := true

var API_BASE_URL: String = RAILWAY_URL if USE_REMOTE else LOCAL_URL

var token: String = ""
var user: Dictionary = {}

# Токен сохраняется локально, чтобы не заставлять игрока логиниться заново
# при каждом запуске игры. Это безопасно: файл хранит только подписанный
# сервером токен (HMAC), а не пароль — если кто-то вручную подменит файл
# на диске поддельным или чужим токеном, сервер отклонит его по неверной
# подписи при первой же проверке (verify_session), так что подменить личность
# игрока таким способом нельзя.
const SESSION_FILE := "user://session.dat"

func _ready() -> void:
	_load_token_from_disk()

func _load_token_from_disk() -> void:
	if not FileAccess.file_exists(SESSION_FILE):
		return
	var file := FileAccess.open(SESSION_FILE, FileAccess.READ)
	if file:
		token = file.get_as_text().strip_edges()

func _save_token_to_disk() -> void:
	var file := FileAccess.open(SESSION_FILE, FileAccess.WRITE)
	if file:
		file.store_string(token)

func _clear_token_from_disk() -> void:
	if FileAccess.file_exists(SESSION_FILE):
		DirAccess.remove_absolute(SESSION_FILE)

## Проверяет на сервере, что локально сохранённый токен ещё действителен,
## и подтягивает актуальные данные пользователя. Вызывается при старте игры
## (см. login.gd), прежде чем автоматически пускать игрока в лобби.
func verify_session(callback: Callable) -> void:
	if token == "":
		callback.call(false)
		return
	_request("/me", HTTPClient.METHOD_GET, {}, func(code, data):
		if code == 200:
			user = data.get("user", {})
			callback.call(true)
		else:
			token = ""
			_clear_token_from_disk()
			callback.call(false)
	)

# Уровень, который нужно загрузить при входе в world.tscn (устанавливается
# лобби перед сменой сцены). null означает "запусти дефолтный демо-мир".
var pending_level_data = null

# Что редактор должен открыть при входе в editor.tscn.
# null — новый пустой проект.
# {"type": "draft", "draft_id": "..."} — локальный черновик.
# {"type": "published", "game_id": "..."} — уже опубликованная игра (для правок).
var editor_load_request = null

signal login_success(user: Dictionary)
signal login_failed(message: String)
signal register_success(user: Dictionary)
signal register_failed(message: String)
signal logged_out

func is_logged_in() -> bool:
	return token != ""

func _request(path: String, method: int, body: Dictionary = {}, callback: Callable = Callable()) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var headers := ["Content-Type: application/json"]
	if token != "":
		headers.append("Authorization: Bearer " + token)

	var json_body := ""
	if not body.is_empty():
		json_body = JSON.stringify(body)

	var err := http.request(API_BASE_URL + path, headers, method, json_body)
	if err != OK:
		push_error("Ошибка запроса к Platbox API: %s" % err)
		http.queue_free()
		return

	http.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
		var text := body_bytes.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if parsed == null:
			parsed = {}
		if callback.is_valid():
			callback.call(response_code, parsed)
		http.queue_free()
	, CONNECT_ONE_SHOT)

func register(username: String, email: String, password: String) -> void:
	var body := {"username": username, "email": email, "password": password}
	_request("/auth/register", HTTPClient.METHOD_POST, body, func(code, data):
		if code == 201:
			token = data.get("token", "")
			user = data.get("user", {})
			_save_token_to_disk()
			register_success.emit(user)
		else:
			register_failed.emit(data.get("error", "Не удалось создать аккаунт"))
	)

func login(identifier: String, password: String) -> void:
	var body := {"username": identifier, "password": password}
	_request("/auth/login", HTTPClient.METHOD_POST, body, func(code, data):
		if code == 200:
			token = data.get("token", "")
			user = data.get("user", {})
			_save_token_to_disk()
			login_success.emit(user)
		else:
			login_failed.emit(data.get("error", "Не удалось войти"))
	)

func logout() -> void:
	if token != "":
		_request("/auth/logout", HTTPClient.METHOD_POST)
	token = ""
	user = {}
	_clear_token_from_disk()
	logged_out.emit()

func fetch_games(callback: Callable) -> void:
	_request("/games", HTTPClient.METHOD_GET, {}, func(code, data):
		if code == 200:
			callback.call(data.get("games", []))
		else:
			callback.call([])
	)

## Список опубликованных игр текущего пользователя (для экрана "Мои проекты").
func fetch_my_games(callback: Callable) -> void:
	_request("/my-games", HTTPClient.METHOD_GET, {}, func(code, data):
		if code == 200:
			callback.call(data.get("games", []))
		else:
			callback.call([])
	)

## Сохраняет уровень. Если у level.level_id уже есть id существующей игры —
## обновляет её (PUT), иначе создаёт новую запись (POST) и проставляет level_id.
func save_level(level: PlatLevel, callback: Callable) -> void:
	var body := {"title": level.title, "level_data": level.to_dict(), "thumbnail_color": level.thumbnail_color}
	if level.level_id != "":
		_request("/games/" + level.level_id, HTTPClient.METHOD_PUT, body, func(code, data):
			if code == 200:
				callback.call(true, "Сохранено!")
			else:
				callback.call(false, data.get("error", "Не удалось сохранить"))
		)
	else:
		_request("/games", HTTPClient.METHOD_POST, body, func(code, data):
			if code == 201:
				level.level_id = str(data.get("game", {}).get("id", ""))
				callback.call(true, "Опубликовано!")
			else:
				callback.call(false, data.get("error", "Не удалось опубликовать"))
		)

## Переименовывает/меняет цвет обложки опубликованной игры без пересохранения уровня.
func update_game_meta(game_id: String, title: String, thumbnail_color: String, callback: Callable) -> void:
	var body := {"title": title, "thumbnail_color": thumbnail_color}
	_request("/games/" + game_id, HTTPClient.METHOD_PUT, body, func(code, data):
		if code == 200:
			callback.call(true, "Сохранено!")
		else:
			callback.call(false, data.get("error", "Не удалось сохранить"))
	)

## Загружает уровень по id игры для запуска в 3D-мире.
func fetch_level(game_id: String, callback: Callable) -> void:
	_request("/games/" + game_id, HTTPClient.METHOD_GET, {}, func(code, data):
		if code == 200:
			var game: Dictionary = data.get("game", {})
			callback.call(game.get("level_data", null))
		else:
			callback.call(null)
	)
