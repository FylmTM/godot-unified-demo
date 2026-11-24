class_name HeroSpawn
extends Marker3D
## Level marker: where a hero appears when nobody is up to arrive beside (a session's start, everyone down), by input
## slot. The sim reads one per slot (`world_create`).

const UNIFIED_KIND := "hero_spawn"

## The input slot whose hero appears here (0 to 3, one marker each).
@export_range(0, 3) var slot: int = 0
