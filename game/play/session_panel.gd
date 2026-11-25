class_name SessionPanel
extends PanelContainer
## The HUD's plate for a game played with friends, under the crypt's counts: what others join it with (the lobby code
## online, this machine's address on the LAN, "Getting a code..." while it comes, "Closed" after Stop inviting; a
## joiner, what it joined), how many play, and a slow link's warning while the round trip to the host is past what
## plays smoothly. Hidden alone (single player, couch included, until it is opened to friends) and in a replay. The
## plate grows with what it says. It only shows: Copy and Stop inviting are the pause menu's (the HUD takes no clicks).

@onready var _caption: Label = %Caption
@onready var _value: Label = %Value
@onready var _players: Label = %Players
@onready var _slow: Label = %Slow
@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	_session.mode_changed.connect(func(_mode: UnifiedSession.Mode, _detail: String) -> void: _show())
	_session.link_slow_changed.connect(func(_slow_now: bool) -> void: _show())
	_session.roster_changed.connect(_show)  # someone came or went: the count
	_session.sim_event.connect(_on_sim_event)
	Game.invite_changed.connect(_show)
	_show()


func _show() -> void:
	var mode: int = _session.mode
	var joined: bool = mode in [UnifiedSession.MODE_JOIN_ONLINE, UnifiedSession.MODE_JOIN_DIRECT]
	visible = mode != UnifiedSession.MODE_REPLAY and (joined or Game.hosting() or Game.inviting)
	if not visible:
		return
	var code: String = _session.join_code
	if joined:
		_caption.text = "Joined"
		_value.text = Game.join_target if Game.join_target != "" else "A friend's game"
	elif code != "":
		_caption.text = "Code" if mode == UnifiedSession.MODE_HOST_ONLINE else "Address"
		_value.text = code
	elif Game.inviting:
		_caption.text = "Code" if Game.inviting_online else "Address"
		_value.text = "Getting a code..." if Game.inviting_online else "Opening..."
	else:
		_caption.text = "Friends"
		_value.text = "Closed"
	var count: int = _session.get_players().size()
	_players.text = "%d player%s" % [count, "" if count == 1 else "s"]
	_slow.visible = _session.link_slow
	_slow.text = "Slow link: %d ms (smooth up to %d)" % [roundi(_session.round_trip_ms),
		roundi(_session.round_trip_ceiling_ms)]


## A player arrived or left on a confirmed tick: the count. (roster_changed alone misses a new game's first player
## when the last game ended with the same slots taken.)
func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state == UnifiedSession.EVENT_CONFIRMED and (event is EventPlayerJoined or event is EventPlayerLeft):
		_show()
