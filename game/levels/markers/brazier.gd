extends Marker3D
## Level marker: a brazier (braziers.odin), at the foot of the brazier part (its stand) whose bowl it lights: the
## marker and the part share their place. The party lights it by holding Interact beside it, or with a Mage's fireball,
## and a lit one counts toward its gate's need as a pressed plate does; the vault's break the boss's ward. Its fire is
## its view's (game/views/brazier.tscn), never the level's.

const UNIFIED_KIND := "brazier"

## What the brazier works: a `gate` marker, or nothing (the vault's). Anything else fails the level.
@export var target: NodePath
