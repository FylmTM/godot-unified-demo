class_name Hud
extends Control
## The minimal HUD: each local hero's class and HP, the co-op pause, and "press Start to join" while a connected pad
## plays nobody.
##
## It shows session data (Unified.data.hud), the newest prediction, which a rollback can change; nothing here is final,
## so nothing waits for a CONFIRMED event.

@onready var _heroes: Label = %Heroes
@onready var _paused: Label = %Paused
@onready var _join_hint: Label = %JoinHint


func _ready() -> void:
	Unified.data.hud.changed.connect(_show_heroes)
	Unified.session.local_players_changed.connect(_show_join_hint)
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: _show_join_hint())
	_show_heroes()
	_show_join_hint()


## A line per local hero, and the pause.
func _show_heroes() -> void:
	var lines: PackedStringArray = []
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player != 0 and hero.local:
			lines.append("%s   %d HP" % [EnumClass.name(hero.class).capitalize(), hero.hp])
	_heroes.text = "\n".join(lines)
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
