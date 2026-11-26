extends Marker3D
## Level marker: a trap (traps.odin). Spikes stand at the marker, over a spike floor tile (4 m, the spikes in its middle
## 2.2 m): up one second in every three from `phase`, or while a plate that names them is pressed. A roller is a pillar
## that goes along the marker's Path3D child (two points or more, the pillar's foot on the floor) and back, each leg
## taking `leg_s`, from `phase` seconds into its way.

const UNIFIED_KIND := "trap"

## What the trap is: its damage, timing and reach are the sim's (tuning.odin).
@export_enum("spikes", "roller") var kind: String = "spikes"
## How far into its cycle it is at the game's start, in seconds: two traps of one kind side by side take turns.
@export var phase: float = 0.0
## A roller's: the seconds each leg of its path takes.
@export var leg_s: float = 3.0
