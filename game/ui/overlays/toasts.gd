class_name Toasts
extends VBoxContainer
## The column of toasts at the top of the screen, in the lane between the HUD's plates and its counts (Lane: the HUD
## measures it, keep_in), as wide as the lane allows up to its own width, above the co-op pause's banner and the join
## cards and clear of the crypt's middle; newest at the bottom, at most MAX_SHOWN (MAX_SHOWN_NARROW while the lane is
## narrow: a big interface size), the oldest dropped first, also when the column would reach the banner. A toast's text
## is short (a name and a word or two; a long name is cut by NameLabel's rule). It lives with the app
## (game/app/game.tscn's Notices), so a toast outlives a change of scene within a game, on a layer of its own under the
## play scene's menus and the app's overlays: the pause menu dims it as it dims the HUD, and nothing it says covers a
## question. Game clears it when the game is over.

## The most toasts shown at once, and while the lane is narrower than the column's own width.
const MAX_SHOWN: int = 3
const MAX_SHOWN_NARROW: int = 2

## A toast (game/ui/widgets/toast.tscn).
@export var toast_scene: PackedScene

## The column's own width (the scene's), and the lowest its toasts may reach (canvas units: the banner's top).
var _width: float = 0.0
var _bottom: float = INF
var _max_shown: int = MAX_SHOWN


func _ready() -> void:
	_width = offset_right - offset_left
	resized.connect(_trim.call_deferred)


## Shows `text` as a new toast.
func show_toast(text: String) -> void:
	_add(text, "")


## Shows a toast about player `player`: their name (cut to one line of the toast by NameLabel's rule, keeping its
## "+1"), then `after` (" joined (Mage)").
func show_toast_about(player: String, after: String) -> void:
	_add(after, player)


## Drops every toast, and puts the column back in the middle at its own width.
func clear() -> void:
	for toast: Node in get_children():
		toast.free()
	offset_left = -_width / 2.0
	offset_right = _width / 2.0
	_bottom = INF
	_max_shown = MAX_SHOWN


## Keeps the column in `lane` (Lane: between the HUD's plates), as wide as it allows up to the column's own width (a
## toast's text wraps), and above `bottom` (the co-op pause's banner): fewer toasts while the lane is narrow.
func keep_in(lane: Lane, bottom: float) -> void:
	lane.centre(self, minf(_width, lane.width()))
	_bottom = bottom
	_max_shown = MAX_SHOWN if lane.width() >= _width else MAX_SHOWN_NARROW
	_trim()


func _add(text: String, player: String) -> void:
	var toast: Toast = toast_scene.instantiate()
	add_child(toast)
	toast.set_text(text, player, offset_right - offset_left)
	_trim()


## Drops the oldest toasts past the most shown, or reaching below the banner (the newest always shows).
func _trim() -> void:
	while get_child_count() > 1 and (get_child_count() > _max_shown or position.y + size.y > _bottom):
		var oldest: Node = get_child(0)
		remove_child(oldest)
		oldest.queue_free()
		size.y = get_combined_minimum_size().y
