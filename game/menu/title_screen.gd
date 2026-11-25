class_name TitleScreen
extends MenuScreen
## The title screen: the game's name over the backdrop, and what a player can do from here. Continue (only while the
## save slot holds a crypt, its line under it: "Floor 1 · Surge 7 · 312 felled") and New game open hero select (where
## the couch's players take their seats); New game over a save asks first, as its first surge replaces the save.
## Play together hosts or joins a game with friends; Settings opens the settings over it; Quit leaves the app. The
## version is the build's (project.godot's config/version).
##
## The screens it opens are the menu's to open (it asks with signals). Continue, else New game, is the screen's first
## focus.

## The player asked to continue the saved crypt (hero select, then the game on the save).
signal continue_requested
## The player asked for a new game (hero select).
signal new_game_requested
## The player asked to play with friends (hosting or joining: the Play together screen).
signal play_together_requested
## The player asked for the settings.
signal settings_requested

@onready var _continue: Button = %Continue
@onready var _save_line: Label = %SaveLine
@onready var _new_game: Button = %NewGame
@onready var _play_together: Button = %PlayTogether
@onready var _settings: Button = %Settings
@onready var _quit: Button = %Quit
@onready var _version: Label = %Version


func _ready() -> void:
	if Game.saves.setup != null:
		first_focus = _continue
	super()
	_show_save()
	visibility_changed.connect(_show_save)  # back from a screen over it: a save may have come meanwhile
	_continue.pressed.connect(continue_requested.emit)
	_new_game.pressed.connect(_ask_new_game)
	_play_together.pressed.connect(play_together_requested.emit)
	_settings.pressed.connect(settings_requested.emit)
	_quit.pressed.connect(Game.quit_app)
	_version.text = "Version %s" % ProjectSettings.get_setting("application/config/version")


## Continue and the save's line, while the slot holds a crypt.
func _show_save() -> void:
	var saved: bool = Game.saves.setup != null
	_continue.visible = saved
	_save_line.visible = saved
	_save_line.text = Game.saves.summary()
	if saved:
		set_first_focus(_continue)


## A new game, asking first when the slot holds a crypt: the new game's first surge replaces it.
func _ask_new_game() -> void:
	if Game.saves.setup == null:
		new_game_requested.emit()
		return
	Game.ask("Start a new crypt?", "Your saved crypt (%s) is replaced at the new game's first surge."
		% Game.saves.summary(), "New game", "Back", func(confirmed: bool) -> void:
			if confirmed:
				new_game_requested.emit())
