class_name LiftView
extends Node3D
## The lift's view (View_Lift, simulation/extension/frame.odin): the host poses this root at the middle of the deck's
## top, turned as the deck is, so the wooden deck sinks down its shaft as the rules move it. While it goes down
## (EnumLiftPhase.DESCENDING) it creaks, a creak every CREAK_EVERY_S, the first as it sets off; its stop at the bottom
## is the play scene's thud (the lift's Choosing event).

## How often the deck creaks while it goes down, in seconds.
const CREAK_EVERY_S: float = 0.9

## Set by the host before _ready and anew each time the lift's view data changes.
var data: ViewLift:
	set(value):
		data = value
		if is_node_ready():
			_show()

@onready var _creaks: Timer = $Creaks


func _ready() -> void:
	_creaks.wait_time = CREAK_EVERY_S
	_creaks.timeout.connect(Sfx.play.bind(&"creak"))
	_show()


func _show() -> void:
	if data == null:
		return
	var moving: bool = data.phase == EnumLiftPhase.DESCENDING
	if moving and _creaks.is_stopped():
		Sfx.play(&"creak")
		_creaks.start()
	elif not moving:
		_creaks.stop()
