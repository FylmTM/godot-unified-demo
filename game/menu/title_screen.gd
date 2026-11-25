class_name TitleScreen
extends MenuScreen
## The title screen: the game's name over the backdrop, and what a player can do from here. New game opens hero select
## (where the couch's players take their seats); Settings opens the settings over it; Quit leaves the app. The version
## is the build's (project.godot's config/version).
##
## The screens it opens are the menu's to open (it asks with signals). New game is the screen's first focus.

## The player asked for a new game (hero select).
signal new_game_requested
## The player asked for the settings.
signal settings_requested

@onready var _new_game: Button = %NewGame
@onready var _settings: Button = %Settings
@onready var _quit: Button = %Quit
@onready var _version: Label = %Version


func _ready() -> void:
	super()
	_new_game.pressed.connect(new_game_requested.emit)
	_settings.pressed.connect(settings_requested.emit)
	_quit.pressed.connect(Game.quit_app)
	_version.text = "Version %s" % ProjectSettings.get_setting("application/config/version")
