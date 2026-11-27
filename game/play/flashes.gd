class_name Flashes
extends RefCounted
## The flashes setting's numbers (Settings.flashes): what a hit's flash is drawn at. The crowd's shader and an elite's
## overlay ask here; with flashes off Effects plays no light pulse and a hero plate no hurt pulse.

## A hit's flash with flashes off: half as bright.
const DIMMED: float = 0.5

## Settings.flashes, as play.gd last set it (views read it here: they don't reach the autoloads).
static var on: bool = true


## How bright a hit's flash is drawn with flashes `on` (Settings.flashes): full, or DIMMED.
static func strength(on: bool) -> float:
	return 1.0 if on else DIMMED
