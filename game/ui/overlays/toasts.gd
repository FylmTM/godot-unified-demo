class_name Toasts
extends VBoxContainer
## The column of toasts low in the middle of the screen (clear of the HUD's corners and its banner at the top), newest
## at the bottom; it keeps at most MAX_SHOWN, dropping the oldest. It lives with the app's overlays, so a toast
## outlives a change of scene within a game; Game clears it when the game is over.

## The most toasts shown at once.
const MAX_SHOWN: int = 4

## A toast (game/ui/widgets/toast.tscn).
@export var toast_scene: PackedScene


## Shows `text` as a new toast.
func show_toast(text: String) -> void:
	if get_child_count() >= MAX_SHOWN:
		get_child(0).free()
	var toast: Toast = toast_scene.instantiate()
	toast.set_text(text)
	add_child(toast)


## Drops every toast.
func clear() -> void:
	for toast: Node in get_children():
		toast.free()
