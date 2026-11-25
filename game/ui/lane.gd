class_name Lane
extends RefCounted
## The HUD's lane: the room at the top of the view between the hero plates (left) and the crypt's counts with the
## session panel (right), in canvas units. The toasts, the co-op pause's banner and the link plate keep to it, centred
## in it and no wider, so at any interface size they cover no plate. Hud measures it; Game hands it to the overlays.

## The room kept free from the plates on either side.
const MARGIN: float = 24.0

## The lane's left and right edges.
var left: float = 0.0
var right: float = 0.0


func _init(from: float, to: float) -> void:
	left = from
	right = to


## How wide a thing in the lane may be.
func width() -> float:
	return maxf(right - left - 2.0 * MARGIN, 0.0)


## Centres `control` (anchored at the view's top middle, growing both ways) in the lane, `wide` across (its own size
## when negative: it grows both ways from the lane's middle).
func centre(control: Control, wide: float = -1.0) -> void:
	var from_middle: float = (left + right - control.get_viewport_rect().size.x) / 2.0
	var half: float = maxf(wide, 0.0) / 2.0
	control.offset_left = from_middle - half
	control.offset_right = from_middle + half
