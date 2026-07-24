extends Node
## Session — глобальный синглтон (autoload).
## Хранит токен авторизации и данные игрока, общается с Platbox API.

# Публичный адрес бэкенда на Railway. Замени "твой-проект" на реальный поддомен
# после деплоя (Railway → Settings → Networking → Generate Domain).
const RAILWAY_URL := "https://твой-проект.up.railway.app/api"

# Для локальной разработки на ПК: http://127.0.0.1:3000/api
# Для Android-эмулятора с локальным сервером: http://10.0.2.2:3000/api
const LOCAL_URL := "http://127.0.0.1:3000/api"

# Переключатель: true — всегда бить в Railway, false — в локальный сервер.
# Удобно на время разработки поставить false, а перед сборкой релиза — true.
const USE_REMOTE := true

var API_BASE_URL: String = RAILWAY_URL if USE_REMOTE else LOCAL_URL

var token: String = ""
var user: Dictionary = {}

# Уровень, который нужно загрузить при входе в world.tscn (устанавливается
# лобби перед сменой сцены). null означает "запусти дефолтный демо-мир".
var pending_level_data = null

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
			login_success.emit(user)
		else:
			login_failed.emit(data.get("error", "Не удалось войти"))
	)

func logout() -> void:
	if token != "":
		_request("/auth/logout", HTTPClient.METHOD_POST)
	token = ""
	user = {}
	logged_out.emit()

func fetch_games(callback: Callable) -> void:
	_request("/games", HTTPClient.METHOD_GET, {}, func(code, data):
		if code == 200:
			callback.call(data.get("games", []))
		else:
			callback.call([])
	)

## Сохраняет уровень. Если у level.level_id уже есть id существующей игры —
## обновляет её (PUT), иначе создаёт новую запись (POST) и проставляет level_id.
func save_level(level: PlatLevel, callback: Callable) -> void:
	var body := {"title": level.title, "level_data": level.to_dict()}
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

## Загружает уровень по id игры для запуска в 3D-мире.
func fetch_level(game_id: String, callback: Callable) -> void:
	_request("/games/" + game_id, HTTPClient.METHOD_GET, {}, func(code, data):
		if code == 200:
			var game: Dictionary = data.get("game", {})
			callback.call(game.get("level_data", null))
		else:
			callback.call(null)
	)
