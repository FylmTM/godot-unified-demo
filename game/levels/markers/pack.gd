extends Marker3D
## Level marker: a pack of skeletons asleep where the floor begins. The sim lays its members out on rings around the
## marker (director.odin, pack_places: they must fit on the walkable floor, or the level fails to load) and wakes the
## whole pack when a hero comes into sight or one of them is hit.

const UNIFIED_KIND := "pack"

## How many skeletons the pack holds.
@export_range(1, 12) var count: int = 4
