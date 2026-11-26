class_name FireballView
extends Node3D
## A fireball in flight (View_Fireball, simulation/extension/frame.odin): a burning orb lobbed from the Mage's hands to
## where it lands. The kind is script-posed (Posed_By.Script): the host leaves this root alone, and the script puts it on
## the flight's parabola at the session's shown time, from `from` to `to` in Unified.constants.fireball_flight seconds,
## FLIGHT_ARC above the straight line at its top. So the orb is a function of the view data and the shown time: after a
## rollback or a replay seek it shows where the flight is, and a pause holds it in the air. The burst is the play
## scene's, on the sim's Event_Fireball_Burst.

## How high the flight rises above the straight line from the hands to the landing, at its middle (metres).
const FLIGHT_ARC: float = 2.5

## Set by the host before _ready, and anew each time the fireball's view data changes.
var data: ViewFireball


func _process(_delta: float) -> void:
	var age: float = (Unified.session.shown_time - data.cast_at) / Unified.tick_hz
	var along: float = clampf(age / Unified.constants.fireball_flight, 0.0, 1.0)
	global_position = data.from.lerp(data.to, along) + Vector3.UP * (4.0 * FLIGHT_ARC * along * (1.0 - along))


## The host's pose (the hands, where the row was made) is not where the orb is: the flight puts it in _process.
func _sim_pose(_position: Vector3, _rotation: Quaternion) -> void:
	pass
