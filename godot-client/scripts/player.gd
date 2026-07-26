extends CharacterBody3D
## Контроллер персонажа: ходьба, прыжок, камера от третьего лица.
## Ввод унифицирован: работает и с клавиатуры (WASD + мышь),
## и с виртуального джойстика на телефоне (см. touch_controls.gd).

const SPEED := 6.0
const JUMP_VELOCITY := 8.0
const MOUSE_SENSITIVITY := 0.003
const ROTATION_SPEED := 10.0

const MAX_HEALTH := 100

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var mesh: MeshInstance3D = $MeshInstance3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Здоровье ---
var health: int = MAX_HEALTH
var spawn_position: Vector3 = Vector3.ZERO

signal health_changed(new_health: int, max_health: int)
signal player_died

# Виртуальный джойстик (мобильные устройства) пишет сюда напрямую.
var touch_move_vector: Vector2 = Vector2.ZERO
var touch_jump_requested: bool = false

func _ready() -> void:
	add_to_group("player")
	spawn_position = global_position
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -1.2, 0.6)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var jump_pressed := Input.is_action_just_pressed("jump") or touch_jump_requested
	if jump_pressed and is_on_floor():
		velocity.y = JUMP_VELOCITY
	touch_jump_requested = false

	var input_dir := Vector2.ZERO
	if OS.has_feature("mobile") or touch_move_vector.length() > 0.05:
		input_dir = touch_move_vector
	else:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var cam_basis := camera_pivot.global_transform.basis
	var direction := (cam_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction.y = 0

	if direction.length() > 0.01:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		var target_angle := atan2(direction.x, direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_angle, ROTATION_SPEED * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * delta * 6)
		velocity.z = move_toward(velocity.z, 0, SPEED * delta * 6)

	move_and_slide()

	# Простая защита от падения за пределы мира — телепорт на старт.
	if global_position.y < -20:
		respawn()

## --- Система здоровья ---

func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health = max(0, health - amount)
	health_changed.emit(health, MAX_HEALTH)
	if health <= 0:
		player_died.emit()
		# Небольшая задержка перед респауном, чтобы был понятен момент смерти.
		await get_tree().create_timer(1.0).timeout
		respawn()

func heal(amount: int) -> void:
	if health <= 0:
		return
	health = min(MAX_HEALTH, health + amount)
	health_changed.emit(health, MAX_HEALTH)

func respawn() -> void:
	health = MAX_HEALTH
	health_changed.emit(health, MAX_HEALTH)
	global_position = spawn_position
	velocity = Vector3.ZERO
