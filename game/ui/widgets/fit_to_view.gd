class_name FitToView
extends Node
## Keeps its parent control on the view: when a large interface size makes the parent's content (its combined minimum
## size) bigger than the view less MARGIN on each side (the prompt bar's room above and below), the parent scales down
## about its `pivot` until it fits; never up. A child of a centred panel's CenterContainer (its pivot the middle) or of
## the title's column (its left middle). The parent must not sit in a container, which would reset its scale.

## The room kept free on each side, in canvas units: the prompt bar's height above and below.
const MARGIN: Vector2 = Vector2(48.0, 96.0)

## Where the parent shrinks toward, as a share of its size: (0.5, 0.5) its middle.
@export var pivot: Vector2 = Vector2(0.5, 0.5)


func _ready() -> void:
	var target: Control = get_parent() as Control
	target.resized.connect(_fit)
	target.minimum_size_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	var target: Control = get_parent() as Control
	var natural: Vector2 = target.get_combined_minimum_size()
	if natural.x <= 0.0 or natural.y <= 0.0:
		return
	var room: Vector2 = target.get_viewport_rect().size - 2.0 * MARGIN
	var fit: float = minf(1.0, minf(room.x / natural.x, room.y / natural.y))
	target.pivot_offset = target.size * pivot
	target.scale = Vector2(fit, fit)
