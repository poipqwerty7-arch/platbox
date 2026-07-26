class_name DraftStore
extends RefCounted
## Черновики уровней хранятся ЛОКАЛЬНО на компьютере игрока (user://drafts/),
## а не в базе данных на сервере — так и должно быть по задумке: черновик
## существует только у автора, пока он сам не решит опубликовать игру.
##
## Публикация (Session.save_level → POST/PUT /api/games) — это единственный
## путь, которым данные уровня вообще попадают на сервер, так что подделать
## публикацию через локальный файл нельзя: сервер всегда берёт author_id
## из проверенного токена авторизации, а не из присланных данных.

const DRAFTS_DIR := "user://drafts"

static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DRAFTS_DIR):
		DirAccess.make_dir_recursive_absolute(DRAFTS_DIR)

## Список всех локальных черновиков (для экрана "Мои проекты").
static func list_drafts() -> Array:
	_ensure_dir()
	var result := []
	var dir := DirAccess.open(DRAFTS_DIR)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var data := load_draft_raw(file_name.trim_suffix(".json"))
			if not data.is_empty():
				result.append(data)
		file_name = dir.get_next()
	dir.list_dir_end()

	result.sort_custom(func(a, b): return a.get("updated_at", "") > b.get("updated_at", ""))
	return result

## Сохраняет уровень как черновик. Если draft_id пуст — создаёт новый файл
## и возвращает свежесгенерированный id, иначе перезаписывает существующий.
static func save_draft(level: PlatLevel, draft_id: String) -> String:
	_ensure_dir()
	var id := draft_id if draft_id != "" else "draft_%d" % Time.get_ticks_msec()
	var payload := {
		"draft_id": id,
		"updated_at": Time.get_datetime_string_from_system(),
		"level": level.to_dict(),
	}
	var file := FileAccess.open(DRAFTS_DIR + "/" + id + ".json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(payload))
	return id

## Возвращает сырые метаданные черновика (для списка "Мои проекты").
static func load_draft_raw(draft_id: String) -> Dictionary:
	var path := DRAFTS_DIR + "/" + draft_id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

## Загружает черновик как полноценный PlatLevel для открытия в редакторе.
static func load_draft_level(draft_id: String) -> PlatLevel:
	var data := load_draft_raw(draft_id)
	if data.is_empty():
		return null
	return PlatLevel.from_dict(data.get("level", {}))

static func delete_draft(draft_id: String) -> void:
	var path := DRAFTS_DIR + "/" + draft_id + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
