class_name PlatRule
extends RefCounted
## Визуальное правило "Когда [Trigger] -> Сделай [Action]".
## Это безопасная замена текстовому скриптингу: игрок конструирует поведение
## из готовых блоков вместо того, чтобы писать исполняемый код, который
## пришлось бы запускать на устройствах других игроков.

enum Trigger {
	TOUCH,         # игрок коснулся объекта
	ZONE_ENTER,    # игрок вошёл в зону (Area3D без физического тела)
	ZONE_EXIT,     # игрок вышел из зоны
}

enum Action {
	DAMAGE,        # нанести урон игроку (param: количество)
	HEAL,          # восстановить здоровье (param: количество)
	GIVE_COINS,    # выдать монеты (param: количество) — согласовывается с сервером
	TELEPORT,      # телепортировать к объекту с id = param
	DESTROY_SELF,  # удалить этот объект из мира
	RESPAWN_PLAYER,# вернуть игрока на точку спавна
}

var trigger: int = Trigger.TOUCH
var action: int = Action.DAMAGE
var param: String = "10"   # значение параметра; тип зависит от action (число или id объекта)

func _init(p_trigger: int = Trigger.TOUCH, p_action: int = Action.DAMAGE, p_param: String = "10") -> void:
	trigger = p_trigger
	action = p_action
	param = p_param

func to_dict() -> Dictionary:
	return {"trigger": trigger, "action": action, "param": param}

static func from_dict(data: Dictionary) -> PlatRule:
	return PlatRule.new(
		data.get("trigger", Trigger.TOUCH),
		data.get("action", Action.DAMAGE),
		str(data.get("param", "10"))
	)

## Выполняет действие над игроком, который вызвал триггер.
## player — CharacterBody3D игрока (должен быть в группе "player").
func execute(player: Node3D) -> void:
	match action:
		Action.DAMAGE:
			if player.has_method("take_damage"):
				player.take_damage(int(param))
		Action.HEAL:
			if player.has_method("heal"):
				player.heal(int(param))
		Action.GIVE_COINS:
			# Монеты за игру пока не начисляются автоматически — см. README/DEPLOY:
			# выдача монет идёт только через администратора/базу данных на старте.
			# Здесь оставлен хук на будущее, когда появится согласование с сервером.
			push_warning("GIVE_COINS: выдача монет из игрового правила пока не подключена к серверу")
		Action.TELEPORT:
			var target := player.get_tree().get_first_node_in_group("plat_object_%s" % param)
			if target:
				player.global_position = target.global_position + Vector3(0, 1, 0)
		Action.DESTROY_SELF:
			pass # обрабатывается на уровне вызывающего объекта, не здесь
		Action.RESPAWN_PLAYER:
			if player.has_method("respawn"):
				player.respawn()

## Человекочитаемое описание правила — используется в UI редактора.
func describe() -> String:
	var trigger_text: String = {
		Trigger.TOUCH: "Когда игрок касается",
		Trigger.ZONE_ENTER: "Когда игрок входит в зону",
		Trigger.ZONE_EXIT: "Когда игрок выходит из зоны",
	}[trigger]

	var action_text: String = {
		Action.DAMAGE: "нанести урон %s" % param,
		Action.HEAL: "восстановить здоровье %s" % param,
		Action.GIVE_COINS: "выдать %s монет" % param,
		Action.TELEPORT: "телепортировать к объекту %s" % param,
		Action.DESTROY_SELF: "удалить объект",
		Action.RESPAWN_PLAYER: "вернуть на точку спавна",
	}[action]

	return "%s → %s" % [trigger_text, action_text]
