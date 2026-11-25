class_name StickSteps
extends RefCounted
## Left and right as steps through a list (hero select's seats, the HUD's join cards): one step per press of a key or a
## button, and one per push of a stick, each pad's own. A stick sends a stream of motion while held, each past its
## dead zone a "press" to Godot; this steps only when the stick crosses ui_left's or ui_right's dead zone from below,
## and again only once it has come back inside it (or crossed to the other side).

## Each pad's stick, by its id: the side it is pushed to now (-1 left, +1 right, 0 inside the dead zone).
var _held: Dictionary[int, int] = {}


## The step `event` makes: -1 left, +1 right, 0 none.
func step_of(event: InputEvent) -> int:
	if event is InputEventJoypadMotion:
		if not (event.is_action(&"ui_left") or event.is_action(&"ui_right")):
			return 0
		var side: int = -1 if event.is_action_pressed(&"ui_left") else 1 if event.is_action_pressed(&"ui_right") else 0
		var was: int = _held.get(event.device, 0)
		_held[event.device] = side
		return side if side != was else 0
	if event.is_action_pressed(&"ui_left"):
		return -1
	if event.is_action_pressed(&"ui_right"):
		return 1
	return 0
