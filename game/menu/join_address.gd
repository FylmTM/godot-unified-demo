class_name JoinAddressScreen
extends MenuScreen
## Join a game on this network by its host's address: a host (a name or a number) and maybe a port (Game.LAN_PORT when
## none), always handed on as `host:port`. The field starts with the last address this machine joined, selected (so
## typing replaces it), and keeps what was typed when a join fails (the menu comes back here, the dialog over it saying
## why). Enter in the field, or Join, joins; Join waits for something that reads as an address. Esc (or a pad's B) in
## the field goes back, as it does anywhere on the screen.

## The player asked to join `address` (`host:port`; hero select first).
signal join_requested(address: String)

@onready var _address: LineEdit = %Address
@onready var _problem: Label = %Problem
@onready var _join: Button = %Join
@onready var _back: Button = %Back


func _ready() -> void:
	super()
	if not Settings.last_join_online:
		_address.text = Settings.last_join
	_address.text_changed.connect(func(_text: String) -> void: _show_address())
	_address.text_submitted.connect(func(_text: String) -> void: _try_join())
	_address.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed(&"ui_cancel"):
			_address.accept_event()
			back_requested.emit())
	_address.focus_entered.connect(_address.select_all.call_deferred)
	_join.pressed.connect(_try_join)
	_back.pressed.connect(back_requested.emit)
	_show_address()


## The address typed, as it joins: `host:port`, the port LAN_PORT when it names none ("": it isn't one).
func address() -> String:
	var typed: String = _address.text.strip_edges()
	if not _readable(typed):
		return ""
	return typed if typed.contains(":") else "%s:%d" % [typed, Game.LAN_PORT]


func _try_join() -> void:
	if address() != "":
		join_requested.emit(address())


## Join waits for an address: a host and a port when one is given.
func _show_address() -> void:
	var typed: String = _address.text.strip_edges()
	var readable: bool = _readable(typed)
	_join.disabled = not readable
	_problem.text = "" if readable or typed == "" else "That isn't an address: a host and maybe a port, 192.168.1.5:7777."
	_problem.visible = _problem.text != ""


## A host (no spaces) and maybe a port (1 to 65535).
static func _readable(typed: String) -> bool:
	var parts: PackedStringArray = typed.split(":")
	if typed == "" or parts.size() > 2 or parts[0] == "" or typed.contains(" "):
		return false
	return parts.size() == 1 or (parts[1].is_valid_int() and parts[1].to_int() > 0 and parts[1].to_int() < 65_536)
