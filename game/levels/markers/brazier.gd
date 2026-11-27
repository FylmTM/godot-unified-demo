extends Marker3D
## Level marker: a brazier, standing beside the brazier part whose bowl it lights. The party lights it as a second way
## to open its gate: lit, it will count toward the gate's need as a pressed plate does (docs/plan.md, milestone 7: no
## rule lights it yet). The vault's braziers work no gate.

const UNIFIED_KIND := "brazier"

## What the brazier works: a `gate` marker, or nothing (the vault's). Anything else fails the level.
@export var target: NodePath
