class_name FriendsScreen
extends MenuScreen
## The pause menu's Invite friends, for a game this machine plays alone or hosts: open it to friends online (a lobby
## code; offered only where online play can start, else greyed with the library's sentence) or on this network (this
## machine's address), the code or address shown large with Copy (its button says "Copied" a moment), and Stop
## inviting, which lets nobody new in (the players in stay); inviting again opens it the way it was hosted. The game
## goes on meanwhile; "Getting a code..." shows until the code comes. Everything it shows is the game's state
## (Game.inviting, invite_problem, the session's join_code): an opening that failed says why here, once.

## How long Copy says "Copied" (seconds).
const COPIED_S: float = 1.5

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
	_copy.pressed.connect(_copy_code)
	_online.pressed.connect(Game.invite.bind(true))
	_lan.pressed.connect(Game.invite.bind(false))
	_stop.pressed.connect(Game.stop_inviting)
	_back.pressed.connect(back_requested.emit)
	Game.invite_changed.connect(_show)
	_show()


## Copies the code (Game.clipboard_set), and says so on the button a moment.
func _copy_code() -> void:
	Game.clipboard_set(_session.join_code)
	_copy.text = "Copied"
	await get_tree().create_timer(COPIED_S).timeout
	if is_instance_valid(_copy):
		_copy.text = "Copy"


func _show() -> void:
	if not is_inside_tree():
		return  # the menu closed: Game's signals reach it until it is freed
	var code: String = _session.join_code
	var online_problem: String = _session.online_problem
	_code.text = code if code != "" else ("Getting a code..." if Game.inviting_online else "Opening...")
	_code.visible = code != "" or Game.inviting
	_copy.visible = code != ""
	_stop.visible = Game.inviting
	if code != "":
		_caption.text = ("Friends join with this code." if _session.mode == UnifiedSession.MODE_HOST_ONLINE
			else "Friends on this network join this address.")
	elif Game.inviting:
		_caption.text = "Opening the game to friends."
	elif Game.hosting():
		_caption.text = "Nobody new can join. Invite again to let them in."
	else:
		_caption.text = "Open this game to friends: they join you where you are."
	# Inviting again opens it the way it was hosted; alone, either way.
	var hosted_online: bool = _session.mode == UnifiedSession.MODE_HOST_ONLINE
	_online.visible = not Game.inviting and (not Game.hosting() or hosted_online)
	_lan.visible = not Game.inviting and (not Game.hosting() or _session.mode == UnifiedSession.MODE_HOST_DIRECT)
	_online.disabled = online_problem != ""
	_online.focus_mode = Control.FOCUS_NONE if _online.disabled else Control.FOCUS_ALL
	_problem.text = Game.invite_problem if Game.invite_problem != "" else (online_problem if _online.visible
		and online_problem != "" else "")
	_problem.visible = _problem.text != ""
	var focus: Control = get_viewport().gui_get_focus_owner()
	if is_visible_in_tree() and (focus == null or not focus.is_visible_in_tree()):
		_back.grab_focus()  # the button that had it hid
