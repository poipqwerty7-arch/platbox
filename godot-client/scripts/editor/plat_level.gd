class_name PlatLevel
extends RefCounted
## Модель целого уровня — аналог "Workspace" + сохранённого .rbxl файла в Roblox.
## Хранит список объектов (Workspace), плюс отдельные разделы данных,
## по духу похожие на ServerStorage/ReplicatedStorage из Roblox:
##   - workspace_objects: видимые игровые объекты (аналог Workspace)
##   - replicated_data: данные, которые известны и клиенту, и серверу
##     (например, настройки уровня, видимые всем игрокам)
##   - server_data: данные, которые не должны попадать на клиент напрямую
##     (например, приватные конфиги; сейчас не используется рантаймом,
##     задел на будущее для настоящего мультиплеера с авторитетным сервером)

const FORMAT_VERSION := "2.0"

var level_id: String = ""
var title: String = "Без названия"
var author: String = ""
var thumbnail_color: String = "#6c5ce7"
var spawn_point: Vector3 = Vector3(0, 3, 0)
var workspace_objects: Array[PlatObject] = []   # аналог Workspace в Roblox
var replicated_data: Dictionary = {}             # аналог ReplicatedStorage (клиент+сервер видят)
var server_data: Dictionary = {}                 # аналог ServerStorage (только сервер; на будущее)

func add_object(obj: PlatObject) -> void:
	workspace_objects.append(obj)

func remove_object(obj_id: String) -> void:
	workspace_objects = workspace_objects.filter(func(o): return o.id != obj_id)

func find_object(obj_id: String) -> PlatObject:
	for obj in workspace_objects:
		if obj.id == obj_id:
			return obj
	return null

func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"level_id": level_id,
		"title": title,
		"author": author,
		"thumbnail_color": thumbnail_color,
		"spawn_point": [spawn_point.x, spawn_point.y, spawn_point.z],
		"workspace": workspace_objects.map(func(o: PlatObject): return o.to_dict()),
		"replicated_data": replicated_data,
		"server_data": server_data,
	}

static func from_dict(data: Dictionary) -> PlatLevel:
	var level := PlatLevel.new()
	level.level_id = data.get("level_id", "")
	level.title = data.get("title", "Без названия")
	level.author = data.get("author", "")
	level.thumbnail_color = data.get("thumbnail_color", "#6c5ce7")
	var spawn = data.get("spawn_point", [0, 3, 0])
	level.spawn_point = Vector3(spawn[0], spawn[1], spawn[2])
	var objs_data = data.get("workspace", [])
	for obj_dict in objs_data:
		level.workspace_objects.append(PlatObject.from_dict(obj_dict))
	level.replicated_data = data.get("replicated_data", {})
	level.server_data = data.get("server_data", {})
	return level

func to_json() -> String:
	return JSON.stringify(to_dict(), "  ")

static func from_json(json_text: String) -> PlatLevel:
	var parsed = JSON.parse_string(json_text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("Не удалось разобрать JSON уровня")
		return PlatLevel.new()
	return PlatLevel.from_dict(parsed)

## Строит реальную 3D-сцену из этой модели данных, кладёт всё под parent.
func spawn_into(parent: Node3D) -> void:
	for obj in workspace_objects:
		obj.spawn_into(parent)
