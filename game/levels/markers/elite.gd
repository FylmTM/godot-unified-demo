extends Marker3D
## Level marker: an elite skeleton (a Warrior, a Rogue or a Mage, the sim's Elite_Kind by name), asleep where it
## stands, facing the marker's +Z, until a hero comes into sight or it is hit (elites.odin). It must stand on the
## walkable floor, or the level fails to load.

const UNIFIED_KIND := "elite"

## What the elite is: its health, speed and rules are the sim's (ELITE_SPECS and its kind's file).
@export_enum("warrior", "rogue", "mage") var kind: String = "warrior"
