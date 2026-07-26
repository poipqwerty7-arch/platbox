extends Control
## Виртуальный джойстик + кнопка прыжка для мобильных устройств.
## Показывается только когда OS.has_feature("mobile") истинно.

@onready var joystick_bg: Control = $JoystickBase
@onready var joystick_knob: Control = $JoystickBase/Knob
@onready var jump_button: Button = $JumpButton

var player: CharacterBody3D
var joystick_active := false
var joystick_touch_index := -1
var joystick_origin := Vector2.ZERO
const JOYSTICK_RADIUS := 60.0

func _ready() -> void:
	visible = OS.has_feature("mobile")
	if not visible:
		return
	player = get_node("../Player")
	jump_button.button_down.connect(func(): player.touch_jump_requested = true)

func _input(event: InputEvent) -> void:
	if not visible or player == null:
		return

	if event is InputEventScreenTouch:
		if event.pressed and joystick_touch_index == -1 and event.position.x < get_viewport_rect().size.x * 0.5:
			joystick_touch_index = event.index
			joystick_active = true
			joystick_origin = event.position
			joystick_bg.global_position = joystick_origin - joystick_bg.size / 2
			joystick_bg.visible = true
		elif not event.pressed and event.index == joystick_touch_index:
			joystick_touch_index = -1
			joystick_active = false
			joystick_knob.position = Vector2.ZERO
			player.touch_move_vector = Vector2.ZERO
			joystick_bg.visible = false

	elif event is InputEventScreenDrag and event.index == joystick_touch_index and joystick_active:
		var offset: Vector2 = event.position - joystick_origin
		offset = offset.limit_length(JOYSTICK_RADIUS)
		joystick_knob.position = offset
		player.touch_move_vector = Vector2(offset.x / JOYSTICK_RADIUS, offset.y / JOYSTICK_RADIUS)
