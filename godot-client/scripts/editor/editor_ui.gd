extends Control
## UI-слой редактора уровней: палитра фигур, панель инструментов,
## инспектор свойств выбранного объекта, конструктор правил.

signal shape_selected(shape: int)
signal tool_selected(tool_id: int)
signal save_requested(title: String)
signal rule_added(rule: PlatRule)
signal rule_removed(index: int)
signal delete_requested
signal duplicate_requested
signal exit_requested
signal workspace_item_selected(obj_id: String)

@onready var inspector_panel: PanelContainer = $InspectorPanel
@onready var pos_x: SpinBox = $InspectorPanel/Margin/VBox/TransformGrid/PosX
@onready var pos_y: SpinBox = $InspectorPanel/Margin/VBox/TransformGrid/PosY
@onready var pos_z: SpinBox = $InspectorPanel/Margin/VBox/TransformGrid/PosZ
@onready var rot_x: SpinBox = $InspectorPanel/Margin/VBox/TransformGrid/RotX
@onready var rot_y: SpinBox = $InspectorPanel/Margin/VBox/TransformGrid/RotY
@onready var rot_z: SpinBox = $InspectorPanel/Margin/VBox/TransformGrid/RotZ
@onready var scale_x: SpinBox = $InspectorPanel/Margin/VBox/TransformGrid/ScaleX
@onready var scale_y: SpinBox = $InspectorPanel/Margin/VBox/TransformGrid/ScaleY
@onready var scale_z: SpinBox = $InspectorPanel/Margin/VBox/TransformGrid/ScaleZ
@onready var color_picker: ColorPickerButton = $InspectorPanel/Margin/VBox/ColorPicker
@onready var rules_list: VBoxContainer = $InspectorPanel/Margin/VBox/RulesList
@onready var delete_button: Button = $InspectorPanel/Margin/VBox/DeleteButton

@onready var workspace_tree: Tree = $WorkspacePanel/Margin/VBox/WorkspaceTree
@onready var context_menu: PopupMenu = $ContextMenu

@onready var trigger_option: OptionButton = $BottomBar/RuleBuilder/TriggerOption
@onready var action_option: OptionButton = $BottomBar/RuleBuilder/ActionOption
@onready var param_input: LineEdit = $BottomBar/RuleBuilder/ParamInput
@onready var add_rule_button: Button = $BottomBar/RuleBuilder/AddRuleButton

@onready var save_dialog: Window = $SaveDialog
@onready var title_input: LineEdit = $SaveDialog/Margin/VBox/TitleInput
@onready var save_confirm_button: Button = $SaveDialog/Margin/VBox/ConfirmButton
@onready var save_status_label: Label = $SaveDialog/Margin/VBox/StatusLabel

var editor_ref: Node3D  # ссылка на level_editor.gd для вызова apply_transform_from_inspector

func _ready() -> void:
	editor_ref = get_parent()
	inspector_panel.visible = false
	save_dialog.visible = false

	$Palette/CubeButton.pressed.connect(func(): shape_selected.emit(PlatObject.Shape.CUBE))
	$Palette/CylinderButton.pressed.connect(func(): shape_selected.emit(PlatObject.Shape.CYLINDER))
	$Palette/SphereButton.pressed.connect(func(): shape_selected.emit(PlatObject.Shape.SPHERE))
	$Palette/WedgeButton.pressed.connect(func(): shape_selected.emit(PlatObject.Shape.WEDGE))
	$Palette/NPCButton.pressed.connect(func(): shape_selected.emit(PlatObject.Shape.NPC))

	$Toolbar/SelectTool.pressed.connect(func(): set_active_tool(0))
	$Toolbar/MoveTool.pressed.connect(func(): set_active_tool(1))
	$Toolbar/RotateTool.pressed.connect(func(): set_active_tool(2))
	$Toolbar/ScaleTool.pressed.connect(func(): set_active_tool(3))

	$Toolbar/SaveButton.pressed.connect(func(): save_dialog.visible = true)
	$Toolbar/ExitButton.pressed.connect(func(): exit_requested.emit())

	save_confirm_button.pressed.connect(func():
		save_requested.emit(title_input.text if title_input.text != "" else "Без названия")
	)

	delete_button.pressed.connect(func(): delete_requested.emit())
	add_rule_button.pressed.connect(_on_add_rule_pressed)

	for spin in [pos_x, pos_y, pos_z, rot_x, rot_y, rot_z, scale_x, scale_y, scale_z]:
		spin.value_changed.connect(func(_v): _on_transform_field_changed())
	color_picker.color_changed.connect(func(c): editor_ref.apply_color_from_inspector(c))

	_populate_trigger_options()
	_populate_action_options()
	_setup_context_menu()
	workspace_tree.item_selected.connect(_on_workspace_item_selected)

func set_active_tool(tool_id: int) -> void:
	tool_selected.emit(tool_id)
	var buttons := [$Toolbar/SelectTool, $Toolbar/MoveTool, $Toolbar/RotateTool, $Toolbar/ScaleTool]
	for i in buttons.size():
		buttons[i].button_pressed = (i == tool_id)

## --- Контекстное меню (правый клик по объекту) ---

func _setup_context_menu() -> void:
	context_menu.clear()
	context_menu.add_item("Дублировать", 0)
	context_menu.add_item("Удалить", 1)
	context_menu.id_pressed.connect(func(id: int):
		if id == 0:
			duplicate_requested.emit()
		elif id == 1:
			delete_requested.emit()
	)

func show_context_menu(screen_pos: Vector2) -> void:
	context_menu.position = Vector2i(screen_pos)
	context_menu.popup()

## --- Панель Workspace (список объектов, как в Roblox Studio) ---

func refresh_workspace(level: PlatLevel, selected_id: String) -> void:
	workspace_tree.clear()
	var root := workspace_tree.create_item()
	workspace_tree.hide_root = true
	for obj in level.workspace_objects:
		var item := workspace_tree.create_item(root)
		var icon_text := "🧍" if obj.shape == PlatObject.Shape.NPC else "◻"
		item.set_text(0, "%s %s" % [icon_text, obj.name])
		item.set_metadata(0, obj.id)
		if obj.id == selected_id:
			item.select(0)

func _on_workspace_item_selected() -> void:
	var item := workspace_tree.get_selected()
	if item:
		var obj_id: String = item.get_metadata(0)
		workspace_item_selected.emit(obj_id)

func _populate_trigger_options() -> void:
	trigger_option.clear()
	trigger_option.add_item("Касание игроком", PlatRule.Trigger.TOUCH)
	trigger_option.add_item("Вход в зону", PlatRule.Trigger.ZONE_ENTER)
	trigger_option.add_item("Выход из зоны", PlatRule.Trigger.ZONE_EXIT)

func _populate_action_options() -> void:
	action_option.clear()
	action_option.add_item("Нанести урон", PlatRule.Action.DAMAGE)
	action_option.add_item("Восстановить здоровье", PlatRule.Action.HEAL)
	action_option.add_item("Выдать монеты", PlatRule.Action.GIVE_COINS)
	action_option.add_item("Телепортировать к объекту", PlatRule.Action.TELEPORT)
	action_option.add_item("Удалить объект", PlatRule.Action.DESTROY_SELF)
	action_option.add_item("Вернуть на спавн", PlatRule.Action.RESPAWN_PLAYER)

func is_mouse_over_ui() -> bool:
	# Простая эвристика: если инспектор или палитра под курсором — не даём редактору
	# интерпретировать клик как выбор объекта в 3D.
	var mouse_pos := get_global_mouse_position()
	for panel in [inspector_panel, $Palette, $Toolbar, $BottomBar, $WorkspacePanel]:
		if panel.visible and panel.get_global_rect().has_point(mouse_pos):
			return true
	return false

## --- Инспектор ---

func show_inspector(obj: PlatObject) -> void:
	inspector_panel.visible = true
	pos_x.value = obj.position.x
	pos_y.value = obj.position.y
	pos_z.value = obj.position.z
	rot_x.value = obj.rotation.x
	rot_y.value = obj.rotation.y
	rot_z.value = obj.rotation.z
	scale_x.value = obj.scale.x
	scale_y.value = obj.scale.y
	scale_z.value = obj.scale.z
	color_picker.color = obj.color
	_refresh_rules_list(obj)

func hide_inspector() -> void:
	inspector_panel.visible = false

func _on_transform_field_changed() -> void:
	var new_pos := Vector3(pos_x.value, pos_y.value, pos_z.value)
	var new_rot := Vector3(rot_x.value, rot_y.value, rot_z.value)
	var new_scale := Vector3(scale_x.value, scale_y.value, scale_z.value)
	editor_ref.apply_transform_from_inspector(new_pos, new_rot, new_scale)

func _refresh_rules_list(obj: PlatObject) -> void:
	for child in rules_list.get_children():
		child.queue_free()
	for i in obj.rules.size():
		var rule: PlatRule = obj.rules[i]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = rule.describe()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var remove_btn := Button.new()
		remove_btn.text = "✕"
		var idx := i
		remove_btn.pressed.connect(func(): rule_removed.emit(idx))
		row.add_child(remove_btn)
		rules_list.add_child(row)

func _on_add_rule_pressed() -> void:
	var trigger_id: int = trigger_option.get_item_id(trigger_option.selected)
	var action_id: int = action_option.get_item_id(action_option.selected)
	var param: String = param_input.text if param_input.text != "" else "10"
	var rule := PlatRule.new(trigger_id, action_id, param)
	rule_added.emit(rule)

func show_save_result(success: bool, message: String) -> void:
	save_status_label.text = message
	save_status_label.modulate = Color(0.4, 0.9, 0.4) if success else Color(0.9, 0.4, 0.4)
	if success:
		await get_tree().create_timer(1.2).timeout
		save_dialog.visible = false
