class_name Toasts
extends VBoxContainer
## The column of toasts at the top of the screen, in the middle: between the HUD's plates and its counts (the HUD keeps
## it in that lane: keep_between), above the join cards and clear of the crypt's middle; newest at the bottom, at most
## MAX_SHOWN, the oldest dropped. A toast's text is short (a name and a word or two). It lives with the app
## (game/app/game.tscn's Notices), so a toast outlives a change of scene within a game, on a layer of its own under the
## play scene's menus and the app's overlays: the pause menu dims it as it dims the HUD, and nothing it says covers a
## question. Game clears it when the game is over.

## The most toasts shown at once.
const MAX_SHOWN: int = 3
## The column's width when the lane allows it, and the room it keeps from the HUD's plates either side (canvas units).
const WIDTH: float = 520.0
const MARGIN: float = 24.0

## A toast (game/ui/widgets/toast.tscn).
@export var toast_scene: PackedScene


## Shows `text` as a new toast.
func show_toast(text: String) -> void:
	if get_child_count() >= MAX_SHOWN:
		get_child(0).free()
	var toast: Toast = toast_scene.instantiate()
	toast.set_text(text)
	add_child(toast)


## Drops every toast, and puts the column back in the middle at its full width.
func clear() -> void:
	for toast: Node in get_children():
		toast.free()
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0


## Keeps the column in the lane between `left` and `right` (the HUD's plates either side, in canvas units): centred in
## it, as wide as it leaves room for up to WIDTH (a toast's text wraps), so a big interface size never puts a toast
## over a plate.
func keep_between(left: float, right: float) -> void:
	var width: float = clampf(right - left - 2.0 * MARGIN, 0.0, WIDTH)
	var from_middle: float = (left + right - get_viewport_rect().size.x) / 2.0
	offset_left = from_middle - width / 2.0
	offset_right = from_middle + width / 2.0
