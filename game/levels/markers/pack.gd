extends Marker3D
## Level marker: a pack of skeletons asleep where the floor begins, woken by a hero who comes into sight.

const UNIFIED_KIND := "pack"

## How many skeletons the pack holds.
@export_range(1, 12) var count: int = 4
