class_name PlateView
extends Node3D
## A pressure plate's view (View_Plate, simulation/extension/frame.odin): the decorated stone, posed by the host at the
## sim's slab, so it sinks under a load exactly as the slab does and rises back as it does: the sinking is how a
## pressed plate reads (nothing glows: glow is for what gives light). Its click is the play scene's, on the sim's
## Event_Plate.

## Set by the host before _ready, and anew each time the plate's view data changes.
var data: ViewPlate
