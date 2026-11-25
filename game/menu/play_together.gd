class_name PlayTogetherScreen
extends MenuScreen
## Play together, from the title: host a game for friends (online, by a lobby code; or on this network, by this
## machine's address), join one (with a code, or an address), or rejoin the last one this machine joined. Online play
## is offered only where it can start (UnifiedSession.online_problem): otherwise its rows are greyed and the library's
## sentence says why, read when the screen opens, so a menu never offers what fails after a click. The screen only
## asks: the menu opens what each asks for (hero select first, every time).

## The player asked to host a game (`online`: by a lobby code; else on this network).
signal host_requested(online: bool)
## The player asked to type a code, or an address, to join.
signal join_code_requested
signal join_address_requested
## The player asked to join `target` again (Settings.last_join: a code when `online`, else an address).
signal rejoin_requested(target: String, online: bool)

@onready var _host_online: Button = %HostOnline
@onready var _host_lan: Button = %HostLan
@onready var _join_code: Button = %JoinCode
@onready var _join_address: Button = %JoinAddress
@onready var _rejoin: Button = %Rejoin
@onready var _online_problem: Label = %OnlineProblem
@onready var _back: Button = %Back


func _ready() -> void:
	super()
	_host_online.pressed.connect(host_requested.emit.bind(true))
	_host_lan.pressed.connect(host_requested.emit.bind(false))
	_join_code.pressed.connect(join_code_requested.emit)
	_join_address.pressed.connect(join_address_requested.emit)
	_rejoin.pressed.connect(func() -> void: rejoin_requested.emit(Settings.last_join, Settings.last_join_online))
	_back.pressed.connect(back_requested.emit)
	_show()
	visibility_changed.connect(_show)  # back from a game: the one it joined is the last one now
	set_first_focus(_first_enabled())
	_first_enabled().grab_focus()


## The online rows and the library's sentence, and the last game to rejoin; a greyed row takes no focus.
func _show() -> void:
	var problem: String = Unified.session.online_problem
	for online: Button in [_host_online, _join_code]:
		online.disabled = problem != ""
	_online_problem.text = problem
	_online_problem.visible = problem != ""
	var last: String = Settings.last_join
	_rejoin.visible = last != ""
	_rejoin.disabled = last == "" or (Settings.last_join_online and problem != "")
	_rejoin.text = "Rejoin %s" % last
	for row: Button in [_host_online, _host_lan, _join_code, _join_address, _rejoin]:
		row.focus_mode = Control.FOCUS_NONE if row.disabled else Control.FOCUS_ALL


## The first row that can be pressed.
func _first_enabled() -> Button:
	for row: Button in [_host_online, _host_lan, _join_code, _join_address]:
		if not row.disabled:
			return row
	return _back
