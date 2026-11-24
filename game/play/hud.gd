class_name Hud
extends Control
## The minimal HUD: each local hero's class and HP (or that it is down), the skeletons up and the kills, the co-op
## pause, and "press Start to join" while a connected pad plays nobody.
##
## It shows session data (Unified.data.hud), the newest prediction, which a rollback can change; nothing here is final,
## so nothing waits for a CONFIRMED event.

@onready var _heroes: Label = %Heroes
@onready var _crypt: Label = %Crypt
@onready var _paused: Label = %Paused
@onready var _join_hint: Label = %JoinHint


func _ready() -> void:
	Unified.data.hud.changed.connect(_show_heroes)
	Unified.session.local_players_changed.connect(_show_join_hint)
	Input.joy_connection_changed.connect(_show_join_hint.unbind(2))
	_show_heroes()
	_show_join_hint()


## A line per local hero, the crypt's count, and the pause.
func _show_heroes() -> void:
	var lines: PackedStringArray = []
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player != 0 and hero.local:
			var health: String = "%d HP" % hero.hp if hero.hp > 0 else "down"
			lines.append("%s   %s" % [EnumClass.name(hero.class).capitalize(), health])
	_heroes.text = "\n".join(lines)
	_crypt.text = "Skeletons %d   Kills %d" % [Unified.data.hud.minions, Unified.data.hud.kills]
	_paused.visible = Unified.data.hud.paused


## The hint shows while a connected pad is no local player's own device.
func _show_join_hint() -> void:
	var playing: Array[int] = []
	for local: int in Unified.session.get_local_indices():
		playing.append(Unified.session.get_local_device(local))
	var idle: bool = false
	for device: int in Input.get_connected_joypads():
		idle = idle or device not in playing
	_join_hint.visible = idle
