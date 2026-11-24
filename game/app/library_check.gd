extends Node
## The first autoload: says so when the game library is missing, instead of a wall of parse errors.
##
## Without the game's GDExtension (an export that lost its library, or a checkout that never built it) UnifiedSession
## and the sim's classes don't exist, so the Game autoload, which names them, fails to load and nothing can run. This
## script names no class of the library: it checks for one by name, and when it is missing unloads the main scene and
## shows one panel with the reason and Quit. With the library present it frees itself.


func _ready() -> void:
	if ClassDB.class_exists(&"UnifiedSession"):
		queue_free()
		return
	var exported: bool = OS.has_feature("template")
	push_error("Crypt Crew: the game library failed to load (UnifiedSession missing): %s"
		% ("the export is broken" if exported else "build it with ./uni build"))
	get_tree().unload_current_scene.call_deferred()
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	var title := Label.new()
	title.theme_type_variation = &"InkHeading"
	title.text = "The game library failed to load"
	rows.add_child(title)
	var detail := Label.new()
	detail.theme_type_variation = &"Ink"
	detail.text = ("This copy of the game is incomplete or damaged: download it again." if exported
		else "Build it first: ./uni build")
	rows.add_child(detail)
	var quit := Button.new()
	quit.theme_type_variation = &"DangerButton"
	quit.text = "Quit"
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.pressed.connect(get_tree().quit)
	rows.add_child(quit)
	quit.grab_focus.call_deferred()
