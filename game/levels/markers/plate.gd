extends Marker3D
## Level marker: a pressure plate (plates.odin), a slab resting a hand above the floor that sinks under any weight past
## the sim's PLATE_LOAD (a prop, a hero, an elite). It works its target while pressed: a gate opens once enough of its
## plates are, spikes rise. Its slab is 2 m square, centred on the marker, which stands on the floor.

const UNIFIED_KIND := "plate"

## What the plate works: a `gate` marker, or a `trap` marker of kind spikes. Anything else fails the level.
@export var target: NodePath
