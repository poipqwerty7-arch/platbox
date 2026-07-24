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

# --- Гизмо перемещения (стрелки по осям X/Y/Z, как в Roblox Studio) ---
const GIZMO_LENGTH := 1.5
const GIZMO_AXIS_DIRS := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}
const GIZMO_AXIS_COLORS := {"x": Color(0.9, 0.2, 0.2), "y": Color(0.2, 0.85, 0.25), "z": Color(0.2, 0.45, 0.95)}
var gizmo_handles: Dictionary = {}  # "x"/"y"/"z" -> Area3D
var dragging_axis: String = ""
var drag_axis_origin: Vector3 = Vector3.ZERO
var drag_offset: Vector3 = Vector3.ZERO

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
	_build_move_gizmo()

## Строит три перетаскиваемые стрелки-оси (Area3D на отдельном физическом слое 2,
## чтобы не путались с рейкастом выбора объектов, который смотрит только слой 1).
func _build_move_gizmo() -> void:
	for axis in ["x", "y", "z"]:
		var dir: Vector3 = GIZMO_AXIS_DIRS[axis]
		var color: Color = GIZMO_AXIS_COLORS[axis]
		var align := Quaternion(Vector3.UP, dir)

		var handle := Area3D.new()
		handle.name = "Axis_%s" % axis
		handle.collision_layer = 2
		handle.collision_mask = 0
		handle.set_meta("gizmo_axis", axis)

		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		var shaft := MeshInstance3D.new()
		var shaft_mesh := CylinderMesh.new()
		shaft_mesh.top_radius = 0.05
		shaft_mesh.bottom_radius = 0.05
		shaft_mesh.height = GIZMO_LENGTH
		shaft.mesh = shaft_mesh
		shaft.quaternion = align
		shaft.position = dir * (GIZMO_LENGTH / 2.0)
		shaft.material_override = mat
		handle.add_child(shaft)

		var tip := MeshInstance3D.new()
		var tip_mesh := CylinderMesh.new()
		tip_mesh.top_radius = 0.0
		tip_mesh.bottom_radius = 0.15
		tip_mesh.height = 0.35
		tip.mesh = tip_mesh
		tip.quaternion = align
		tip.position = dir * GIZMO_LENGTH
		tip.material_override = mat
		handle.add_child(tip)

		var col := CollisionShape3D.new()
		var col_shape := CylinderShape3D.new()
		col_shape.radius = 0.16
		col_shape.height = GIZMO_LENGTH + 0.35
		col.shape = col_shape
		col.quaternion = align
		col.position = dir * (GIZMO_LENGTH / 2.0)
		handle.add_child(col)

		gizmo.add_child(handle)
		gizmo_handles[axis] = handle

	_update_gizmo_visibility()

func _setup_ui() -> void:
	ui.shape_selected.connect(_on_shape_selected)
	ui.tool_selected.connect(_on_tool_selected)
	ui.save_requested.connect(_on_save_requested)
	ui.rule_added.connect(_on_rule_added)
	ui.rule_removed.connect(_on_rule_removed)
	ui.delete_requested.connect(_on_delete_requested)
	ui.duplicate_requested.connect(_on_duplicate_requested)
	ui.exit_requested.connect(_on_exit_requested)
	ui.workspace_item_selected.connect(_on_workspace_item_selected)
	ui.refresh_workspace(level, "")

## --- Добавление объектов ---

func _on_shape_selected(shape: int) -> void:
	var obj := PlatObject.new()
	obj.shape = shape
	obj.name = ["Куб", "Цилиндр", "Сфера", "Клин", "NPC"][shape]
	obj.position = _spawn_position_in_front_of_camera()
	level.add_object(obj)
	var node := obj.spawn_into(objects_root)
	_select(obj, node)
	ui.refresh_workspace(level, obj.id)

func _spawn_position_in_front_of_camera() -> Vector3:
	var forward := -camera.global_transform.basis.z
	return camera.global_position + forward * 6.0

## --- Выбор объектов ---

func _select(obj: PlatObject, node: StaticBody3D) -> void:
	selected_object = obj
	selected_node = node
	gizmo.global_position = node.global_position
	ui.show_inspector(obj)
	ui.refresh_workspace(level, obj.id)
	_update_gizmo_visibility()

func _deselect() -> void:
	selected_object = null
	selected_node = null
	ui.hide_inspector()
	ui.refresh_workspace(level, "")
	_update_gizmo_visibility()

func _update_gizmo_visibility() -> void:
	# Стрелки-гизмо реализованы пока только для инструмента Move.
	# Rotate/Scale по-прежнему меняются точными полями в инспекторе справа.
	gizmo.visible = selected_object != null and current_tool == Tool.MOVE

func _on_workspace_item_selected(obj_id: String) -> void:
	var obj := level.find_object(obj_id)
	if not obj:
		return
	var node := objects_root.get_children().filter(func(n): return n.has_meta("plat_object_id") and n.get_meta("plat_object_id") == obj_id)
	if node.size() > 0:
		_select(obj, node[0])

func _on_duplicate_requested() -> void:
	if not selected_object:
		return
	var original := selected_object
	var clone := PlatObject.from_dict(original.to_dict())
	clone.id = PlatObject._generate_id()
	clone.position = original.position + Vector3(1.5, 0, 1.5)  # небольшое смещение, чтобы не наложился на оригинал
	level.add_object(clone)
	var node := clone.spawn_into(objects_root)
	_select(clone, node)

func _input(event: InputEvent) -> void:
	_handle_camera_input(event)

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: ui.set_active_tool(Tool.SELECT)
			KEY_2: ui.set_active_tool(Tool.MOVE)
			KEY_3: ui.set_active_tool(Tool.SCALE)
			KEY_4: ui.set_active_tool(Tool.ROTATE)

	if event is InputEventMouseButton and not ui.is_mouse_over_ui():
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not _try_start_gizmo_drag(event.position):
					_try_select_at_mouse(event.position)
			else:
				if dragging_axis != "":
					dragging_axis = ""
					ui.show_inspector(selected_object)  # обновляем поля инспектора финальными значениями
		elif event.button_index == MOUSE_BUTTON_RIGHT and not cam_dragging and event.pressed:
			_try_context_menu_at_mouse(event.position)

	if event is InputEventMouseMotion and dragging_axis != "":
		_update_gizmo_drag(event.position)

## Пытается начать перетаскивание стрелки гизмо. Возвращает true, если попали
## по стрелке (тогда клик не должен также интерпретироваться как выбор объекта).
func _try_start_gizmo_drag(mouse_pos: Vector2) -> bool:
	if current_tool != Tool.MOVE or not selected_object:
		return false

	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var to := from + dir * 1000.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := space_state.intersect_ray(query)

	if result and result.collider.has_meta("gizmo_axis"):
		dragging_axis = result.collider.get_meta("gizmo_axis")
		drag_axis_origin = selected_node.global_position
		var axis_dir: Vector3 = GIZMO_AXIS_DIRS[dragging_axis]
		var closest := _closest_point_on_axis(drag_axis_origin, axis_dir, from, dir)
		drag_offset = drag_axis_origin - closest
		return true
	return false

func _update_gizmo_drag(mouse_pos: Vector2) -> void:
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var axis_dir: Vector3 = GIZMO_AXIS_DIRS[dragging_axis]
	var closest := _closest_point_on_axis(drag_axis_origin, axis_dir, from, dir)
	var new_pos := closest + drag_offset

	selected_node.global_position = new_pos
	selected_object.position = new_pos
	gizmo.global_position = new_pos

## Находит точку на прямой (axis_origin + s*axis_dir), ближайшую к лучу мыши
## (ray_origin + t*ray_dir). Стандартная формула ближайших точек двух прямых —
## именно так рассчитывается перетаскивание гизмо в большинстве 3D-редакторов.
func _closest_point_on_axis(axis_origin: Vector3, axis_dir: Vector3, ray_origin: Vector3, ray_dir: Vector3) -> Vector3:
	var d1 := axis_dir.normalized()
	var d2 := ray_dir.normalized()
	var r := axis_origin - ray_origin
	var a := d1.dot(d1)
	var b := d1.dot(d2)
	var c := d2.dot(d2)
	var d := d1.dot(r)
	var e := d2.dot(r)
	var denom := a * c - b * b
	if abs(denom) < 0.0001:
		return axis_origin
	var s := (b * e - c * d) / denom
	return axis_origin + d1 * s

func _try_context_menu_at_mouse(mouse_pos: Vector2) -> void:
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
			ui.show_context_menu(mouse_pos)

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
	_update_gizmo_visibility()

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
