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
var current_draft_id: String = ""  # если открыт локальный черновик — его id для перезаписи при Save Draft
var selected_object: PlatObject = null
var selected_node: Node3D = null
var current_tool: int = Tool.SELECT

# --- Гизмо трансформации (Move/Rotate/Scale — как в Roblox Studio) ---
const GIZMO_LENGTH := 1.5
const ROTATE_RADIUS := 1.0
const SCALE_HANDLE_DIST := 1.2
const GIZMO_AXIS_DIRS := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}
const GIZMO_AXIS_COLORS := {"x": Color(0.9, 0.2, 0.2), "y": Color(0.2, 0.85, 0.25), "z": Color(0.2, 0.45, 0.95)}
const MOVE_LAYER_BIT := 2
const ROTATE_LAYER_BIT := 4
const SCALE_LAYER_BIT := 8

var gizmo_move_handles: Dictionary = {}
var gizmo_rotate_handles: Dictionary = {}
var gizmo_scale_handles: Dictionary = {}

# Перетаскивание Move
var dragging_axis: String = ""
var drag_axis_origin: Vector3 = Vector3.ZERO
var drag_offset: Vector3 = Vector3.ZERO

# Перетаскивание Rotate
var dragging_rotate_axis: String = ""
var rotate_plane_origin: Vector3 = Vector3.ZERO
var rotate_reference_dir: Vector3 = Vector3.ZERO
var rotate_start_object_rotation: Vector3 = Vector3.ZERO

# Перетаскивание Scale
var dragging_scale_axis: String = ""
var scale_drag_axis_origin: Vector3 = Vector3.ZERO
var scale_start_distance: float = 0.0
var scale_start_object_scale: Vector3 = Vector3.ONE

# Камера в редакторе летает свободно (fly cam), а не привязана к персонажу.
const CAM_SPEED := 10.0
const CAM_ROTATE_SPEED := 0.003
var cam_rotation := Vector2.ZERO
var cam_dragging := false

func _ready() -> void:
	_setup_ui()
	_build_move_gizmo()
	_build_rotate_gizmo()
	_build_scale_gizmo()
	_load_requested_project()

## Определяет, что открывать: новый пустой проект, локальный черновик
## или уже опубликованную игру (запрос кладётся в Session перед сменой сцены
## из экрана "Мои проекты" или из лобби).
func _load_requested_project() -> void:
	var request = Session.editor_load_request
	Session.editor_load_request = null

	if request == null:
		level = PlatLevel.new()
		level.title = "Новый уровень"
		level.author = Session.user.get("username", "anon") if Session.is_logged_in() else "anon"
		_rebuild_scene()
		ui.refresh_workspace(level, "")
		return

	if request.get("type") == "draft":
		current_draft_id = request.get("draft_id", "")
		var loaded := DraftStore.load_draft_level(current_draft_id)
		level = loaded if loaded else PlatLevel.new()
		_rebuild_scene()
		ui.refresh_workspace(level, "")
		return

	if request.get("type") == "test_return":
		var snapshot: Dictionary = request.get("level_data", {})
		level = PlatLevel.from_dict(snapshot.get("level_data", {}))
		current_draft_id = snapshot.get("draft_id", "")
		_rebuild_scene()
		ui.refresh_workspace(level, "")
		return

	if request.get("type") == "published":
		# Пока грузим с сервера — показываем пустой уровень, чтобы редактор не падал.
		level = PlatLevel.new()
		level.title = "Загрузка..."
		_rebuild_scene()
		var game_id: String = request.get("game_id", "")
		Session.fetch_level(game_id, func(level_data):
			if level_data != null:
				level = PlatLevel.from_dict(level_data)
			else:
				level = PlatLevel.new()
			level.level_id = game_id  # id всегда берём из запроса — на случай, если в старых данных он был пуст
			_rebuild_scene()
			ui.refresh_workspace(level, "")
		)

## Строит три перетаскиваемые стрелки-оси (Area3D на отдельном физическом слое 2,
## чтобы не путались с рейкастом выбора объектов, который смотрит только слой 1).
func _build_move_gizmo() -> void:
	for axis in ["x", "y", "z"]:
		var dir: Vector3 = GIZMO_AXIS_DIRS[axis]
		var color: Color = GIZMO_AXIS_COLORS[axis]
		var align := Quaternion(Vector3.UP, dir)

		var handle := Area3D.new()
		handle.name = "Axis_%s" % axis
		handle.collision_layer = MOVE_LAYER_BIT
		handle.collision_mask = 0
		handle.set_meta("gizmo_axis", axis)

		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # видно с обеих сторон (кольцо Rotate — плоское)
		mat.no_depth_test = true                       # видно сквозь блоки, чтобы гизмо не терялся внутри объекта
		# no_depth_test работает надёжно только в прозрачном проходе рендера —
		# непрозрачные материалы обычно проходят через depth pre-pass, который
		# перебивает эффект. Переводим в альфа-прозрачность (alpha=1.0, визуально
		# всё равно непрозрачный), чтобы гарантированно рисовался поверх геометрии.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.render_priority = 100

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
		gizmo_move_handles[axis] = handle

	_update_gizmo_visibility()

## Строит три кольца вращения вокруг X/Y/Z. Клик засчитывается по плоскому
## диску-коллайдеру (упрощение вместо честной тор-формы — для перетаскивания
## достаточно, т.к. важен сам факт клика по нужной оси, а не точная форма кольца).
func _build_rotate_gizmo() -> void:
	for axis in ["x", "y", "z"]:
		var normal: Vector3 = GIZMO_AXIS_DIRS[axis]
		var color: Color = GIZMO_AXIS_COLORS[axis]
		var align := Quaternion(Vector3.UP, normal)

		var handle := Area3D.new()
		handle.name = "Rotate_%s" % axis
		handle.collision_layer = ROTATE_LAYER_BIT
		handle.collision_mask = 0
		handle.set_meta("gizmo_rotate_axis", axis)

		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # видно с обеих сторон (кольцо Rotate — плоское)
		mat.no_depth_test = true                       # видно сквозь блоки, чтобы гизмо не терялся внутри объекта
		# no_depth_test работает надёжно только в прозрачном проходе рендера —
		# непрозрачные материалы обычно проходят через depth pre-pass, который
		# перебивает эффект. Переводим в альфа-прозрачность (alpha=1.0, визуально
		# всё равно непрозрачный), чтобы гарантированно рисовался поверх геометрии.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.render_priority = 100

		var ring := MeshInstance3D.new()
		ring.mesh = _build_ring_mesh(ROTATE_RADIUS, 0.05, 32)
		ring.quaternion = align
		ring.material_override = mat
		handle.add_child(ring)

		var col := CollisionShape3D.new()
		var col_shape := CylinderShape3D.new()
		col_shape.radius = ROTATE_RADIUS + 0.1
		col_shape.height = 0.12
		col.shape = col_shape
		col.quaternion = align
		handle.add_child(col)

		gizmo.add_child(handle)
		gizmo_rotate_handles[axis] = handle

	_update_gizmo_visibility()

## Строит три кубика-рукоятки на концах осей — тянешь дальше от центра,
## объект растёт по этой оси; тянешь к центру — уменьшается.
func _build_scale_gizmo() -> void:
	for axis in ["x", "y", "z"]:
		var dir: Vector3 = GIZMO_AXIS_DIRS[axis]
		var color: Color = GIZMO_AXIS_COLORS[axis]

		var handle := Area3D.new()
		handle.name = "Scale_%s" % axis
		handle.collision_layer = SCALE_LAYER_BIT
		handle.collision_mask = 0
		handle.set_meta("gizmo_scale_axis", axis)

		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # видно с обеих сторон (кольцо Rotate — плоское)
		mat.no_depth_test = true                       # видно сквозь блоки, чтобы гизмо не терялся внутри объекта
		# no_depth_test работает надёжно только в прозрачном проходе рендера —
		# непрозрачные материалы обычно проходят через depth pre-pass, который
		# перебивает эффект. Переводим в альфа-прозрачность (alpha=1.0, визуально
		# всё равно непрозрачный), чтобы гарантированно рисовался поверх геометрии.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.render_priority = 100

		var stem := MeshInstance3D.new()
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.04
		stem_mesh.bottom_radius = 0.04
		stem_mesh.height = SCALE_HANDLE_DIST
		stem.mesh = stem_mesh
		stem.quaternion = Quaternion(Vector3.UP, dir)
		stem.position = dir * (SCALE_HANDLE_DIST / 2.0)
		stem.material_override = mat
		handle.add_child(stem)

		var cube := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.28
		cube.mesh = box
		cube.position = dir * SCALE_HANDLE_DIST
		cube.material_override = mat
		handle.add_child(cube)

		var col := CollisionShape3D.new()
		var col_shape := BoxShape3D.new()
		col_shape.size = Vector3.ONE * 0.35
		col.shape = col_shape
		col.position = dir * SCALE_HANDLE_DIST
		handle.add_child(col)

		gizmo.add_child(handle)
		gizmo_scale_handles[axis] = handle

	_update_gizmo_visibility()

## Строит плоское кольцо (annulus) вручную через SurfaceTool — не полагаемся
## на TorusMesh (это примитив без гарантий наличия во всех версиях Godot 4;
## самодельная геометрия работает одинаково везде). Кольцо строится в плоскости
## XZ с нормалью по Y — тем же соглашением, что и остальные хендлы гизмо,
## которые потом поворачиваются через Quaternion(Vector3.UP, ось).
func _build_ring_mesh(radius: float, thickness: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := radius - thickness
	var outer := radius + thickness
	for i in segments:
		var a0 := i * TAU / segments
		var a1 := (i + 1) * TAU / segments
		var p0_out := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var p1_out := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		var p0_in := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var p1_in := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		st.add_vertex(p0_out)
		st.add_vertex(p1_out)
		st.add_vertex(p0_in)
		st.add_vertex(p1_out)
		st.add_vertex(p1_in)
		st.add_vertex(p0_in)
	st.generate_normals()
	return st.commit()

func _setup_ui() -> void:
	ui.tool_selected.connect(_on_tool_selected)
	ui.save_requested.connect(_on_save_requested)
	ui.draft_save_requested.connect(_on_draft_save_requested)
	ui.rule_added.connect(_on_rule_added)
	ui.rule_removed.connect(_on_rule_removed)
	ui.delete_requested.connect(_on_delete_requested)
	ui.duplicate_requested.connect(_on_duplicate_requested)
	ui.exit_requested.connect(_on_exit_requested)
	ui.workspace_item_selected.connect(_on_workspace_item_selected)
	ui.test_play_requested.connect(_on_test_play_requested)
	ui.add_object_requested.connect(_on_add_object_requested)
	ui.rename_requested.connect(_on_rename_requested)

## --- Добавление объектов ---

## Тест-плей: пускаем игрока в его же уровень прямо из редактора, без
## публикации. Снимок текущего состояния (включая несохранённые правки)
## кладём в Session, чтобы после возврата открылся ровно тот же уровень.
func _on_test_play_requested() -> void:
	var snapshot := {"level_data": level.to_dict(), "draft_id": current_draft_id}
	Session.editor_return_data = snapshot
	Session.pending_level_data = snapshot["level_data"]
	Session.is_test_play = true
	get_tree().change_scene_to_file("res://scenes/world.tscn")

const SHAPE_NAMES := ["Куб", "Цилиндр", "Сфера", "Клин", "NPC", "SpawnPoint", "Script", "LocalScript"]

## Единая точка создания объекта — используется и старым способом (палитра,
## сейчас убрана из UI, но метод оставлен на случай горячих клавиш в будущем),
## и новым способом через контекстное меню Workspace (кнопка "+ Добавить").
## parent_id == "" — объект верхнего уровня; иначе — вложен в указанный объект.
func _create_object(shape: int, parent_id: String = "") -> void:
	var obj := PlatObject.new()
	obj.shape = shape
	obj.name = SHAPE_NAMES[shape]
	obj.parent_id = parent_id

	if parent_id != "":
		var parent_obj := level.find_object(parent_id)
		obj.position = parent_obj.position + Vector3(1.0, 0, 1.0) if parent_obj else _compute_spawn_position()
	else:
		obj.position = _compute_spawn_position()

	level.add_object(obj)
	var node := obj.spawn_into(objects_root)

	if node:
		_select(obj, node)
	else:
		# Script/LocalScript не имеют 3D-узла — просто выбираем объект "виртуально",
		# чтобы его можно было переименовать/удалить, но без гизмо в 3D-сцене.
		_select(obj, null)

	ui.refresh_workspace(level, obj.id)

func _on_add_object_requested(shape: int, parent_id: String) -> void:
	_create_object(shape, parent_id)

func _on_rename_requested(obj_id: String, new_name: String) -> void:
	var obj := level.find_object(obj_id)
	if not obj or new_name.strip_edges() == "":
		return
	obj.name = new_name.strip_edges()
	if selected_node and selected_object == obj:
		selected_node.name = obj.name
	ui.refresh_workspace(level, selected_object.id if selected_object else "")

## Определяет, куда заспавнить новый объект: если камера смотрит на уже
## существующий блок — новый объект появляется рядом с точкой попадания
## (с небольшим отступом по нормали поверхности, чтобы не влезть внутрь);
## если смотрит в пустоту — на разумном расстоянии перед камерой, а не
## где-то в произвольной точке мира.
const SPAWN_EMPTY_DISTANCE := 6.0
const SPAWN_SURFACE_OFFSET := 0.6

func _compute_spawn_position() -> Vector3:
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var to := from + dir * 200.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # только сами объекты уровня, не гизмо (те на слоях 2/4/8)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := space_state.intersect_ray(query)

	if result:
		return result.position + result.normal * SPAWN_SURFACE_OFFSET
	return from + dir * SPAWN_EMPTY_DISTANCE

## --- Выбор объектов ---

func _select(obj: PlatObject, node: Node3D) -> void:
	selected_object = obj
	selected_node = node
	if node:
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
	var has_selection := selected_object != null and selected_node != null
	gizmo.visible = has_selection and current_tool in [Tool.MOVE, Tool.ROTATE, Tool.SCALE]
	for axis in gizmo_move_handles:
		gizmo_move_handles[axis].visible = has_selection and current_tool == Tool.MOVE
	for axis in gizmo_rotate_handles:
		gizmo_rotate_handles[axis].visible = has_selection and current_tool == Tool.ROTATE
	for axis in gizmo_scale_handles:
		gizmo_scale_handles[axis].visible = has_selection and current_tool == Tool.SCALE

func _on_workspace_item_selected(obj_id: String) -> void:
	if selected_object and selected_object.id == obj_id:
		# Тот же объект уже выбран — это эхо нашего же программного item.select(0)
		# из refresh_workspace (Tree эмитит item_selected не синхронно, поэтому
		# temporary disconnect не спасает; сравнение по id — надёжная защита).
		return
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
				if _is_dragging():
					_end_drag()
					if selected_object:
						ui.show_inspector(selected_object)  # обновляем поля инспектора финальными значениями
		elif event.button_index == MOUSE_BUTTON_RIGHT and not cam_dragging and event.pressed:
			_try_context_menu_at_mouse(event.position)

	if event is InputEventMouseMotion and _is_dragging():
		_update_gizmo_drag(event.position)

func _is_dragging() -> bool:
	return dragging_axis != "" or dragging_rotate_axis != "" or dragging_scale_axis != ""

func _end_drag() -> void:
	dragging_axis = ""
	dragging_rotate_axis = ""
	dragging_scale_axis = ""

## Пытается начать перетаскивание хендла активного инструмента (Move/Rotate/Scale).
## Возвращает true, если попали по хендлу (тогда клик не интерпретируется как выбор объекта).
func _try_start_gizmo_drag(mouse_pos: Vector2) -> bool:
	if not selected_object or not selected_node:
		# selected_node == null — выбран объект без 3D-представления (Script/
		# LocalScript). Гизмо для таких объектов скрыт через visible=false, но
		# в Godot видимость не отключает физическую коллизию Area3D — так что
		# без этой явной проверки старые (невидимые) хендлы гизмо всё ещё
		# могли бы поймать рейкаст и уронить игру на selected_node.global_position.
		return false
	match current_tool:
		Tool.MOVE:
			return _try_start_move_drag(mouse_pos)
		Tool.ROTATE:
			return _try_start_rotate_drag(mouse_pos)
		Tool.SCALE:
			return _try_start_scale_drag(mouse_pos)
	return false

func _raycast_gizmo_layer(mouse_pos: Vector2, layer_bit: int) -> Dictionary:
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var to := from + dir * 1000.0
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = layer_bit
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var raw := space_state.intersect_ray(query)
	return {
		"hit": not raw.is_empty(),
		"collider": raw.get("collider", null),
		"from": from,
		"dir": dir,
	}

## --- Move: перетаскивание вдоль оси ---

func _try_start_move_drag(mouse_pos: Vector2) -> bool:
	var result := _raycast_gizmo_layer(mouse_pos, MOVE_LAYER_BIT)
	if not result.hit or not result.collider.has_meta("gizmo_axis"):
		return false
	dragging_axis = result.collider.get_meta("gizmo_axis")
	drag_axis_origin = selected_node.global_position
	var axis_dir: Vector3 = GIZMO_AXIS_DIRS[dragging_axis]
	var closest := _closest_point_on_axis(drag_axis_origin, axis_dir, result.from, result.dir)
	drag_offset = drag_axis_origin - closest
	return true

func _update_move_drag(mouse_pos: Vector2) -> void:
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var axis_dir: Vector3 = GIZMO_AXIS_DIRS[dragging_axis]
	var closest := _closest_point_on_axis(drag_axis_origin, axis_dir, from, dir)
	var new_pos := closest + drag_offset

	selected_node.global_position = new_pos
	selected_object.position = new_pos
	gizmo.global_position = new_pos

## --- Rotate: перетаскивание кольца вокруг оси ---

func _try_start_rotate_drag(mouse_pos: Vector2) -> bool:
	var result := _raycast_gizmo_layer(mouse_pos, ROTATE_LAYER_BIT)
	if not result.hit or not result.collider.has_meta("gizmo_rotate_axis"):
		return false
	dragging_rotate_axis = result.collider.get_meta("gizmo_rotate_axis")
	rotate_plane_origin = selected_node.global_position
	rotate_start_object_rotation = selected_object.rotation
	rotate_reference_dir = _ring_hit_direction(dragging_rotate_axis, result.from, result.dir)
	return true

## Проецирует луч мыши на плоскость кольца (через центр объекта, нормаль = ось
## вращения) и возвращает направление от центра до точки попадания — по нему
## считается угол поворота через Vector3.signed_angle_to().
func _ring_hit_direction(axis: String, ray_origin: Vector3, ray_dir: Vector3) -> Vector3:
	var normal: Vector3 = GIZMO_AXIS_DIRS[axis]
	var denom := ray_dir.dot(normal)
	if abs(denom) < 0.0001:
		return Vector3.ZERO
	var t := (rotate_plane_origin - ray_origin).dot(normal) / denom
	var hit_point := ray_origin + ray_dir * t
	return (hit_point - rotate_plane_origin).normalized()

func _update_rotate_drag(mouse_pos: Vector2) -> void:
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var current_dir := _ring_hit_direction(dragging_rotate_axis, from, dir)
	if current_dir == Vector3.ZERO or rotate_reference_dir == Vector3.ZERO:
		return

	var axis_dir: Vector3 = GIZMO_AXIS_DIRS[dragging_rotate_axis]
	var delta_degrees := rad_to_deg(rotate_reference_dir.signed_angle_to(current_dir, axis_dir))

	var new_rot: Vector3 = rotate_start_object_rotation
	match dragging_rotate_axis:
		"x": new_rot.x = rotate_start_object_rotation.x + delta_degrees
		"y": new_rot.y = rotate_start_object_rotation.y + delta_degrees
		"z": new_rot.z = rotate_start_object_rotation.z + delta_degrees

	selected_object.rotation = new_rot
	selected_node.rotation_degrees = new_rot

## --- Scale: перетаскивание рукоятки от/к центру ---

func _try_start_scale_drag(mouse_pos: Vector2) -> bool:
	var result := _raycast_gizmo_layer(mouse_pos, SCALE_LAYER_BIT)
	if not result.hit or not result.collider.has_meta("gizmo_scale_axis"):
		return false
	dragging_scale_axis = result.collider.get_meta("gizmo_scale_axis")
	scale_drag_axis_origin = selected_node.global_position
	scale_start_object_scale = selected_object.scale
	var axis_dir: Vector3 = GIZMO_AXIS_DIRS[dragging_scale_axis]
	var closest := _closest_point_on_axis(scale_drag_axis_origin, axis_dir, result.from, result.dir)
	scale_start_distance = (closest - scale_drag_axis_origin).dot(axis_dir)
	return true

func _update_scale_drag(mouse_pos: Vector2) -> void:
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var axis_dir: Vector3 = GIZMO_AXIS_DIRS[dragging_scale_axis]
	var closest := _closest_point_on_axis(scale_drag_axis_origin, axis_dir, from, dir)
	var current_distance := (closest - scale_drag_axis_origin).dot(axis_dir)
	var delta := current_distance - scale_start_distance

	var new_scale: Vector3 = scale_start_object_scale
	match dragging_scale_axis:
		"x": new_scale.x = max(0.1, scale_start_object_scale.x + delta)
		"y": new_scale.y = max(0.1, scale_start_object_scale.y + delta)
		"z": new_scale.z = max(0.1, scale_start_object_scale.z + delta)

	selected_object.scale = new_scale
	# Масштаб хранится не на самом StaticBody3D, а на его дочерних узлах
	# (см. PlatObject.spawn_into: mesh_instance.scale / collision.scale).
	if selected_node.get_child_count() >= 2:
		selected_node.get_child(0).scale = new_scale  # MeshInstance3D
		selected_node.get_child(1).scale = new_scale  # CollisionShape3D

func _update_gizmo_drag(mouse_pos: Vector2) -> void:
	if dragging_axis != "":
		_update_move_drag(mouse_pos)
	elif dragging_rotate_axis != "":
		_update_rotate_drag(mouse_pos)
	elif dragging_scale_axis != "":
		_update_scale_drag(mouse_pos)

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
	if selected_node:
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
	var deleted_id := selected_object.id
	var deleted_parent := selected_object.parent_id
	# Дети удаляемого объекта не пропадают — поднимаются на уровень его
	# родителя (как при удалении папки с содержимым в проводнике).
	for obj in level.workspace_objects:
		if obj.parent_id == deleted_id:
			obj.parent_id = deleted_parent
	level.remove_object(deleted_id)
	if selected_node:
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
		if success and current_draft_id != "":
			# Игра опубликована — локальный черновик больше не нужен.
			DraftStore.delete_draft(current_draft_id)
			current_draft_id = ""
	)

func _on_draft_save_requested(title: String) -> void:
	level.title = title
	current_draft_id = DraftStore.save_draft(level, current_draft_id)
	ui.show_save_result(true, "Черновик сохранён на этом компьютере")

func _on_exit_requested() -> void:
	get_tree().change_scene_to_file("res://scenes/game_lobby.tscn")
