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
## The player asked to join `target` again (Settings.last_join: a code or an address).
signal rejoin_requested(target: String)

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
	_rejoin.pressed.connect(func() -> void: rejoin_requested.emit(Settings.last_join))
	_back.pressed.connect(back_requested.emit)
	_show()
	visibility_changed.connect(_show)  # back from a join: the game it tried is the last one now


## The online rows and the library's sentence, and the last game to rejoin.
func _show() -> void:
	var problem: String = Unified.session.online_problem
	for online: Button in [_host_online, _join_code]:
		online.disabled = problem != ""
	_online_problem.text = problem
	_online_problem.visible = problem != ""
	var last: String = Settings.last_join
	var rejoinable: bool = last != "" and (Game.is_address(last) or problem == "")
	_rejoin.visible = last != ""
	_rejoin.disabled = not rejoinable
	_rejoin.text = "Rejoin %s" % last
