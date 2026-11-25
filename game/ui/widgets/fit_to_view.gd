class_name FitToView
extends Node
## Keeps its parent control on the view: when a large interface size (or a small window) makes the parent's content
## (its combined minimum size) bigger than the view less MARGIN on each side, the parent scales down about its `pivot`
## until it fits; never up. It refits as the parent's content or the view changes (the interface size changes the
## view's size in canvas units). A child of a centred panel's CenterContainer (pivot: the middle), the title's column
## (its left middle) or the HUD's hero plates (their top left). The parent must not sit in a container, which would
## reset its scale.

## The room kept free on each side of the view, in canvas units: across, a menu's side margin; up and down, the room
## the prompt bar takes at the bottom (kept at the top too, so a centred panel stays centred).
const MARGIN: Vector2 = Vector2(48.0, 96.0)

## Where the parent shrinks toward, as a share of its size: (0.5, 0.5) its middle.
@export var pivot: Vector2 = Vector2(0.5, 0.5)


func _ready() -> void:
	var target: Control = get_parent() as Control
	if target.get_parent() is Container:
		push_error("FitToView: %s sits in a container, which resets its scale" % target.get_path())
		return
	target.resized.connect(_fit)
	target.minimum_size_changed.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	var target: Control = get_parent() as Control
	if target == null or not target.is_inside_tree():
		return
	var natural: Vector2 = target.get_combined_minimum_size()
	if natural.x <= 0.0 or natural.y <= 0.0:
		return
	var room: Vector2 = target.get_viewport_rect().size - 2.0 * MARGIN
	var fit: float = minf(1.0, minf(room.x / natural.x, room.y / natural.y))
	target.pivot_offset = target.size * pivot
	target.scale = Vector2(fit, fit)
