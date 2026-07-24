extends Node3D
## Контроллер редактора уровней Platbox.
## Аналог упрощённого Roblox Studio: палитра фигур, инструменты Move/Rotate/Scale,
## панель свойств с редактором правил (визуальный скриптинг), сохранение в JSON.

enum Tool { SELECT, MOVE, ROTATE, SCALE }

@onready var objects_root: Node3D = $ObjectsRoot
@onready var camera: Camera3D = $EditorCamera
@onready var gizmo: Node3D = $Gizmo
@onready var ui: Control = $UI

var level: PlatLevel
var selected_object: PlatObject = null
var selected_node: StaticBody3D = null
var current_tool: int = Tool.SELECT

# Камера в редакторе летает свободно (fly cam), а не привязана к персонажу.
const CAM_SPEED := 10.0
const CAM_ROTATE_SPEED := 0.003
var cam_rotation := Vector2.ZERO
var cam_dragging := false

func _ready() -> void:
	level = PlatLevel.new()
	level.title = "Новый уровень"
	level.author = Session.user.get("username", "anon") if Session.is_logged_in() else "anon"
	_rebuild_scene()
	_setup_ui()

func _setup_ui() -> void:
	ui.shape_selected.connect(_on_shape_selected)
	ui.tool_selected.connect(_on_tool_selected)
	ui.save_requested.connect(_on_save_requested)
	ui.rule_added.connect(_on_rule_added)
	ui.rule_removed.connect(_on_rule_removed)
	ui.delete_requested.connect(_on_delete_requested)
	ui.exit_requested.connect(_on_exit_requested)

## --- Добавление объектов ---

func _on_shape_selected(shape: int) -> void:
	var obj := PlatObject.new()
	obj.shape = shape
	obj.name = ["Куб", "Цилиндр", "Сфера", "Клин"][shape]
	obj.position = _spawn_position_in_front_of_camera()
	level.add_object(obj)
	var node := obj.spawn_into(objects_root)
	_select(obj, node)

func _spawn_position_in_front_of_camera() -> Vector3:
	var forward := -camera.global_transform.basis.z
	return camera.global_position + forward * 6.0

## --- Выбор объектов ---

func _select(obj: PlatObject, node: StaticBody3D) -> void:
	selected_object = obj
	selected_node = node
	gizmo.visible = true
	gizmo.global_position = node.global_position
	ui.show_inspector(obj)

func _deselect() -> void:
	selected_object = null
	selected_node = null
	gizmo.visible = false
	ui.hide_inspector()

func _input(event: InputEvent) -> void:
	_handle_camera_input(event)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not ui.is_mouse_over_ui():
			_try_select_at_mouse(event.position)

func _try_select_at_mouse(mouse_pos: Vector2) -> void:
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * 1000.0
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)

	if result and result.collider.has_meta("plat_object_id"):
		var obj_id: String = result.collider.get_meta("plat_object_id")
		var obj := level.find_object(obj_id)
		if obj:
			_select(obj, result.collider)
			return
	_deselect()

## --- Инструменты трансформации ---

func _on_tool_selected(tool_id: int) -> void:
	current_tool = tool_id

func _process(delta: float) -> void:
	_process_camera_movement(delta)
	if selected_object and selected_node:
		gizmo.global_position = selected_node.global_position

func _handle_camera_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cam_dragging = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if cam_dragging else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and cam_dragging:
		cam_rotation.x -= event.relative.x * CAM_ROTATE_SPEED
		cam_rotation.y = clamp(cam_rotation.y - event.relative.y * CAM_ROTATE_SPEED, -1.4, 1.4)
		camera.rotation = Vector3(cam_rotation.y, cam_rotation.x, 0)

func _process_camera_movement(delta: float) -> void:
	if not cam_dragging:
		return
	var dir := Vector3.ZERO
	var basis := camera.global_transform.basis
	if Input.is_key_pressed(KEY_W): dir -= basis.z
	if Input.is_key_pressed(KEY_S): dir += basis.z
	if Input.is_key_pressed(KEY_A): dir -= basis.x
	if Input.is_key_pressed(KEY_D): dir += basis.x
	if Input.is_key_pressed(KEY_Q): dir -= basis.y
	if Input.is_key_pressed(KEY_E): dir += basis.y
	camera.global_position += dir.normalized() * CAM_SPEED * delta if dir.length() > 0 else Vector3.ZERO

## --- Изменение трансформа выбранного объекта (вызывается из UI-полей ввода) ---

func apply_transform_from_inspector(new_pos: Vector3, new_rot: Vector3, new_scale: Vector3) -> void:
	if not selected_object:
		return
	selected_object.position = new_pos
	selected_object.rotation = new_rot
	selected_object.scale = new_scale
	_respawn_selected()

func apply_color_from_inspector(new_color: Color) -> void:
	if not selected_object:
		return
	selected_object.color = new_color
	_respawn_selected()

func _respawn_selected() -> void:
	var obj := selected_object
	selected_node.queue_free()
	var node := obj.spawn_into(objects_root)
	_select(obj, node)

## --- Правила (визуальный скриптинг) ---

func _on_rule_added(rule: PlatRule) -> void:
	if not selected_object:
		return
	selected_object.rules.append(rule)
	_respawn_selected()
	ui.show_inspector(selected_object)

func _on_rule_removed(index: int) -> void:
	if not selected_object:
		return
	if index >= 0 and index < selected_object.rules.size():
		selected_object.rules.remove_at(index)
	_respawn_selected()
	ui.show_inspector(selected_object)

## --- Удаление ---

func _on_delete_requested() -> void:
	if not selected_object:
		return
	level.remove_object(selected_object.id)
	selected_node.queue_free()
	_deselect()

## --- Сохранение / выход ---

func _rebuild_scene() -> void:
	for child in objects_root.get_children():
		child.queue_free()
	level.spawn_into(objects_root)

func _on_save_requested(title: String) -> void:
	level.title = title
	Session.save_level(level, func(success: bool, message: String):
		ui.show_save_result(success, message)
	)

func _on_exit_requested() -> void:
	get_tree().change_scene_to_file("res://scenes/game_lobby.tscn")
