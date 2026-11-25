class_name JoinAddressScreen
extends MenuScreen
## Join a game on this network by its host's address (`host:port`, or a host alone: Game.LAN_PORT). The field starts
## with the last address this machine joined, and keeps what was typed when a join fails (the menu comes back here,
## the dialog over it saying why). Enter in the field, or Join, joins; Join waits for something that reads as an
## address.

## The player asked to join `address` (hero select first).
signal join_requested(address: String)

@onready var _address: LineEdit = %Address
@onready var _problem: Label = %Problem
@onready var _join: Button = %Join
@onready var _back: Button = %Back


func _ready() -> void:
	super()
	if Game.is_address(Settings.last_join):
		_address.text = Settings.last_join
	_address.text_changed.connect(func(_text: String) -> void: _show_address())
	_address.text_submitted.connect(func(_text: String) -> void: _try_join())
	_join.pressed.connect(_try_join)
	_back.pressed.connect(back_requested.emit)
	_show_address()


## The address typed, trimmed.
func address() -> String:
	return _address.text.strip_edges()


func _try_join() -> void:
	if _readable(address()):
		join_requested.emit(address())


## Join waits for an address: a host (letters, digits, dots, dashes) and a port when one is given.
func _show_address() -> void:
	var typed: String = address()
	var readable: bool = _readable(typed)
	_join.disabled = not readable
	_problem.text = "" if readable or typed == "" else "That isn't an address: a host and maybe a port, 192.168.1.5:7777."
	_problem.visible = _problem.text != ""


static func _readable(typed: String) -> bool:
	var parts: PackedStringArray = typed.split(":")
	if typed == "" or parts.size() > 2 or parts[0] == "" or typed.contains(" "):
		return false
	return parts.size() == 1 or (parts[1].is_valid_int() and parts[1].to_int() > 0 and parts[1].to_int() < 65_536)
