class_name MenuStack
extends Control
## The screens of a menu, one shown at a time: push() opens a screen over the current one, which waits hidden with the
## focus it had; pop() (Back, Esc, a pad's B) frees the top one and gives the one under it its focus back. The title
## and, in play, the pause menu use one each.
##
## A screen pushed again is a new instance: a screen's state is the settings it shows, read when it opens. Its buttons
## are wired by Game as they enter the tree, guarded, so a screen kept, hidden and shown again stays wired once.

## The screen on top changed (pushed, or popped back to).
signal top_changed(screen: MenuScreen)

## Each screen under the top one, with the control that had the focus when it was covered.
var _covered: Dictionary[MenuScreen, Control] = {}


func _ready() -> void:
	for child: Node in get_children():
		if child is MenuScreen:
			_open(child as MenuScreen)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and get_child_count() > 1:
		get_viewport().set_input_as_handled()
		pop()


## The screen shown.
func top() -> MenuScreen:
	return get_child(get_child_count() - 1) as MenuScreen if get_child_count() > 0 else null


## Opens `scene` (a MenuScreen) over the current screen, and returns it.
func push(scene: PackedScene) -> MenuScreen:
	var under: MenuScreen = top()
	if under != null:
		_covered[under] = get_viewport().gui_get_focus_owner()
		under.hide()
	var screen: MenuScreen = scene.instantiate()
	screen.back_requested.connect(pop)
	add_child(screen)
	_open(screen)
	return screen


## Closes the top screen and shows the one under it, its focus back where it was (the root screen stays).
func pop() -> void:
	if get_child_count() <= 1:
		return
	var screen: MenuScreen = top()
	remove_child(screen)
	screen.queue_free()
	var under: MenuScreen = top()
	under.show()
	var focus: Control = _covered.get(under)
	_covered.erase(under)
	if is_instance_valid(focus) and focus.is_visible_in_tree():
		focus.grab_focus()
	else:
		under.first_focus.grab_focus()
	top_changed.emit(under)


func _open(screen: MenuScreen) -> void:
	if get_viewport().gui_get_focus_owner() == null or not get_viewport().gui_get_focus_owner().is_visible_in_tree():
		screen.first_focus.grab_focus()
	top_changed.emit(screen)
