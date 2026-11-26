class_name BarricadeView
extends Node3D
## A barricade's view (View_Barricade, simulation/extension/frame.odin): the wooden barrier, posed by the host at the
## sim's fence, standing or, once a blow broke it free, tumbling as the debris body does. The break's dust and sound
## are the play scene's, on the sim's Event_Barricade_Broken.

## Set by the host before _ready, and anew each time the barricade's view data changes.
var data: ViewBarricade
