class_name TitleScreen
extends MenuScreen
## The title screen: the game's name over the backdrop, and what a player can do from here. New game starts single
## player (a pad's Start joins more players on the couch once the crypt is up); Settings opens the settings over it;
## Quit leaves the app. The version is the build's (project.godot's config/version).
##
## New game starts through Game, and what happens next follows the session (game/app/game.gd); Settings is the menu's
## to open (it asks with `settings_requested`). New game is the screen's first focus.

## The player asked for the settings.
signal settings_requested

@onready var _new_game: Button = %NewGame
@onready var _settings: Button = %Settings
@onready var _quit: Button = %Quit
@onready var _version: Label = %Version


func _ready() -> void:
	super()
	_new_game.pressed.connect(Game.start_single)
	_settings.pressed.connect(settings_requested.emit)
	_quit.pressed.connect(Game.quit_app)
	_version.text = "Version %s" % ProjectSettings.get_setting("application/config/version")
