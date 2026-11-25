class_name FriendsScreen
extends MenuScreen
## The pause menu's Invite friends, for a game this machine plays alone or hosts: open it to friends online (a lobby
## code; offered only where online play can start, else greyed with the library's sentence) or on this network (this
## machine's address), the code or address shown large with Copy, and Stop inviting, which lets nobody new in (the
## players in stay); inviting again opens it the same way. The game goes on meanwhile. An opening that fails leaves the
## game as it was and says why here (mode_changed's detail).

@onready var _caption: Label = %Caption
@onready var _code: Label = %Code
@onready var _copy: Button = %Copy
@onready var _online: Button = %Online
@onready var _lan: Button = %Lan
@onready var _stop: Button = %Stop
@onready var _problem: Label = %Problem
@onready var _back: Button = %Back
@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	super()
	_copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_session.join_code)
		Game.toast("Copied %s" % _session.join_code))
	_online.pressed.connect(_open.bind(true))
	_lan.pressed.connect(_open.bind(false))
	_stop.pressed.connect(func() -> void: _session.close_online())
	_back.pressed.connect(back_requested.emit)
	_session.mode_changed.connect(_on_mode_changed)
	_session.join_code_changed.connect(func(_code_now: String) -> void: _show())
	_problem.text = ""
	_show()


## Opens the game to friends (`online`: by a lobby code; else on this network), or invites again after Stop inviting.
func _open(online: bool) -> void:
	_problem.text = ""
	if online:
		_session.open_online()
	else:
		_session.open_direct(Game.lan_port)
	_show()


## A mode that didn't change, with a detail, is an opening that failed: it says why.
func _on_mode_changed(_mode: UnifiedSession.Mode, detail: String) -> void:
	if detail != "":
		_problem.text = Game.sentence(detail, "")
	_show()


func _show() -> void:
	var mode: int = _session.mode
	var code: String = _session.join_code
	var hosting: bool = mode in [UnifiedSession.MODE_HOST_ONLINE, UnifiedSession.MODE_HOST_DIRECT]
	var online_problem: String = _session.online_problem
	_code.text = code
	_code.visible = code != ""
	_copy.visible = code != "" and Game.has_clipboard()
	_stop.visible = code != ""
	if code != "":
		_caption.text = ("Friends join with this code." if mode == UnifiedSession.MODE_HOST_ONLINE
			else "Friends on this network join this address.")
	elif hosting:
		_caption.text = "Nobody new can join. Invite again to let them in."
	else:
		_caption.text = "Open this game to friends: they join you where you are."
	# Inviting again opens it the way it was hosted; alone, either way.
	_online.visible = code == "" and mode != UnifiedSession.MODE_HOST_DIRECT
	_lan.visible = code == "" and mode != UnifiedSession.MODE_HOST_ONLINE
	_online.disabled = online_problem != ""
	if _online.visible and online_problem != "" and _problem.text == "":
		_problem.text = online_problem
	_problem.visible = _problem.text != ""
	var focus: Control = get_viewport().gui_get_focus_owner()
	if is_visible_in_tree() and (focus == null or not focus.is_visible_in_tree()):
		_back.grab_focus()  # the button that had it hid
