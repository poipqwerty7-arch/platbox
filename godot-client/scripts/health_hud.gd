extends Control
## Простая полоска здоровья в HUD. Подписывается на сигнал health_changed игрока.

@onready var bar: ProgressBar = $HealthBar
@onready var label: Label = $HealthBar/Label

func _ready() -> void:
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100

func connect_to_player(player: CharacterBody3D) -> void:
	player.health_changed.connect(_on_health_changed)
	_on_health_changed(player.health, 100)

func _on_health_changed(new_health: int, max_health: int) -> void:
	bar.max_value = max_health
	bar.value = new_health
	label.text = "%d / %d HP" % [new_health, max_health]

	# Цвет полоски меняется в зависимости от процента здоровья — понятная обратная связь.
	var pct := float(new_health) / float(max_health)
	var fill_style := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style:
		if pct > 0.5:
			fill_style.bg_color = Color(0.3, 0.8, 0.4)
		elif pct > 0.25:
			fill_style.bg_color = Color(0.95, 0.7, 0.2)
		else:
			fill_style.bg_color = Color(0.9, 0.3, 0.3)
