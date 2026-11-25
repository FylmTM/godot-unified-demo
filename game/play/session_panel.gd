class_name SessionPanel
extends PanelContainer
## The HUD's plate for a game played with friends, under the crypt's counts: what others join it with (the lobby code
## online, this machine's address on the LAN; a joiner, the code or address it joined), how many play, and a slow
## link's warning while the round trip to the host is past what plays smoothly. Hidden alone (single player, couch
## included, until it is opened to friends) and in a replay. It only shows: Copy and Stop inviting are the pause
## menu's (the HUD takes no clicks).

@onready var _caption: Label = %Caption
@onready var _value: Label = %Value
@onready var _players: Label = %Players
@onready var _slow: Label = %Slow
@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	_session.mode_changed.connect(func(_mode: UnifiedSession.Mode, _detail: String) -> void: _show())
	_session.join_code_changed.connect(func(_code: String) -> void: _show())
	_session.link_slow_changed.connect(func(_slow_now: bool) -> void: _show())
	Unified.data.hud.changed.connect(_show)
	_show()


func _show() -> void:
	var mode: int = _session.mode
	visible = mode not in [UnifiedSession.MODE_SINGLE, UnifiedSession.MODE_REPLAY]
	if not visible:
		return
	var joined: bool = mode in [UnifiedSession.MODE_JOIN_ONLINE, UnifiedSession.MODE_JOIN_DIRECT]
	var online: bool = mode in [UnifiedSession.MODE_HOST_ONLINE, UnifiedSession.MODE_JOIN_ONLINE]
	var shown: String = Settings.last_join if joined else _session.join_code
	_caption.text = "Code" if online else "Address"
	_value.text = shown if shown != "" else "Closed to new players"
	var count: int = _session.get_players().size()
	_players.text = "%d player%s" % [count, "" if count == 1 else "s"]
	_slow.visible = _session.link_slow
	_slow.text = "Slow link: %d ms (smooth up to %d)" % [roundi(_session.round_trip_ms),
		roundi(_session.round_trip_ceiling_ms)]
