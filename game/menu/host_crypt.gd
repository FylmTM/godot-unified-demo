class_name HostCryptScreen
extends MenuScreen
## Which crypt a host opens to friends, asked only while the save slot holds a run: the saved run (its line under it),
## where the friends join it, or a new one in the hub (whose run's beginning replaces the save, as a new game's does).

## The player chose: `save` (the slot's) to continue, or null for a new crypt.
signal chosen(save: UnifiedSetup)

@onready var _continue: Button = %Continue
@onready var _save_line: Label = %SaveLine
@onready var _new: Button = %New
@onready var _back: Button = %Back


func _ready() -> void:
	super()
	_save_line.text = Game.saves.summary()
	_continue.pressed.connect(func() -> void: chosen.emit(Game.saves.setup))
	_new.pressed.connect(func() -> void: chosen.emit(null))
	_back.pressed.connect(back_requested.emit)
