class_name TitleScreen
extends Control
## The title screen: the game's name over the backdrop, and what a player can do from here. New game starts single
## player (a pad's Start joins more players on the couch once the crypt is up); Quit leaves the app. The version
## is the build's (project.godot's config/version).
##
## Its buttons only ask Game; what happens next follows the session (game/app/game.gd).

@onready var _new_game: Button = %NewGame
@onready var _quit: Button = %Quit
@onready var _version: Label = %Version


func _ready() -> void:
	_new_game.pressed.connect(Game.start_single)
	_quit.pressed.connect(Game.quit_app)
	_version.text = "Version %s" % ProjectSettings.get_setting("application/config/version")
	_new_game.grab_focus()
