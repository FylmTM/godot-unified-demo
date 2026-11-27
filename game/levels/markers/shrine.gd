extends Marker3D
## Level marker: a hub shrine, where the party sets the next run's mode or difficulty (run.odin). A floor holds one for
## each setting at most.

const UNIFIED_KIND := "shrine"

## What the shrine sets (the sim's Shrine_Setting, by name).
@export_enum("mode", "difficulty") var sets: String = "mode"
