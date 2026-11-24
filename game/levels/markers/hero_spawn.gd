class_name HeroSpawn
extends Marker3D
## Level marker: where the hero of an input slot appears when its player arrives (presence.odin). The sim reads one
## per slot (world.odin), and the play scene's camera frames their middle until a local hero is in.

const UNIFIED_KIND := "hero_spawn"

## The input slot whose hero appears here (0 to 3, one marker each).
@export_range(0, 3) var slot: int = 0
