class_name GateView
extends Node3D
## A gate's view (View_Gate, simulation/extension/frame.odin): the gated wall's iron grille, posed by the host at the
## sim's grille as its motor lifts and lowers it. Everything it shows is the body's pose; its sounds are the play
## scene's, on the sim's Event_Gate.

## Set by the host before _ready, and anew each time the gate's view data changes.
var data: ViewGate
