extends Marker3D
## Level marker: a gate (gates.odin), a grille 4 m wide along the marker's local X, standing on the floor in a 4 m gap
## of the level's walls. It lifts while at least `need` of the plates that name it are pressed, and lowers otherwise.

const UNIFIED_KIND := "gate"

## How many of its plates must be pressed at once to open it (at least one, at most the plates that name it).
@export_range(1, 8) var need: int = 1
## Whether it stays open once opened (until the party enters the floor again), as a vault's door.
@export var latch: bool = false
