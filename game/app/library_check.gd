extends CanvasLayer
## The first autoload: when the game library is missing, it says so in one panel with Quit, over the errors Godot
## prints for every script that names the library's classes.
##
## Without the game's GDExtension (an export that lost its library, or a checkout that never built it) UnifiedSession
## and the sim's classes don't exist, so the Game autoload fails to load and nothing can run. This names no class of
## the library: it checks for one by name. With the library present it frees itself; without it, it unloads the main
## scene and shows its panel (library_check.tscn, so the project's theme checks see its look).

@onready var _detail: Label = %Detail
@onready var _quit: Button = %Quit


func _ready() -> void:
	if ClassDB.class_exists(&"UnifiedSession"):
		queue_free()
		return
	var exported: bool = OS.has_feature("template")
	push_error("Crypt Crew: the game library failed to load (UnifiedSession missing): %s"
		% ("the export is broken" if exported else "build it with ./uni build"))
	get_tree().unload_current_scene.call_deferred()
	_detail.text = ("This copy of the game is incomplete or damaged: download it again." if exported
		else "Build it first: ./uni build")
	_quit.pressed.connect(get_tree().quit)
	show()
	_quit.grab_focus.call_deferred()
