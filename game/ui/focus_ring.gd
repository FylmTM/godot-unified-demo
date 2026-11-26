@tool
class_name FocusRing
extends StyleBox
## The game's focus frame (the theme's focus for buttons, fields and tabs, and the code field's cursor cell): `ring`,
## drawn with its colours breathing slowly.
##
## The pulse lives in the drawing, never in the theme: a theme's item that changes tells every control in the tree
## that its theme changed, hundreds of them each time, which cost milliseconds a frame on every screen. So this box
## never changes while the game runs; each draw sets the clock's strength on a private copy of the ring, which nothing
## listens to, and draws that. The focused control must be redrawn every frame for the pulse to move: Game does it
## (and the code field for its cell). In the editor the ring is drawn as it is, at full strength.

## A full breath, in seconds, and its faintest, as a share of the ring's full strength.
const PULSE_S: float = 1.6
const PULSE_LOW: float = 0.55

## The frame at full strength: its border, corners and glow. A panel wearing the focus frame (the code field's cell)
## is laid out by the ring's own margins, as if it wore the ring itself.
@export var ring: StyleBoxFlat:
	set(value):
		ring = value
		if ring != null:
			for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				set_content_margin(side, ring.get_margin(side))

## The copy of `ring` that is drawn, at the pulse's strength (made on the first draw).
var _lit: StyleBoxFlat = null


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if Engine.is_editor_hint():
		ring.draw(to_canvas_item, rect)
		return
	if _lit == null:
		_lit = ring.duplicate() as StyleBoxFlat
	var t: float = Time.get_ticks_msec() / 1000.0
	var strength: float = lerpf(PULSE_LOW, 1.0, 0.5 + 0.5 * cos(TAU * t / PULSE_S))
	_lit.border_color = Color(ring.border_color, ring.border_color.a * strength)
	_lit.shadow_color = Color(ring.shadow_color, ring.shadow_color.a * strength)
	_lit.draw(to_canvas_item, rect)
