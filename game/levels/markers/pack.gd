extends Marker3D
## Level marker: a pack of skeletons asleep where the floor begins. The sim keeps its place and size among the floor's
## (world.odin, `Places.packs`); the skeletons themselves are milestone 2's next steps (docs/plan.md, Milestone 2: the
## design).

const UNIFIED_KIND := "pack"

## How many skeletons the pack holds.
@export_range(1, 12) var count: int = 4
