class_name Backdrop
extends Node3D
## The menus' backdrop: the crew at the graveyard's gate on a moonlit night, built from the hub kit's parts (not the
## hub a run will start in: nothing here plays), lit as docs/ART.md lights the hub.
##
## The four heroes idle on their own clock, each a little out of step with the others, through the same
## CharacterRig.pose() the game's views use. The camera sways slowly around where it was placed, so the screen is
## alive without drawing the eye from the menu on its left.

## Each hero's idle, by its node's name under Heroes.
const IDLES: Dictionary[StringName, StringName] = {
	&"Knight": Clips.IDLE,
	&"Barbarian": Clips.BARBARIAN_IDLE,
	&"Mage": Clips.IDLE_ALT,
	&"Rogue": Clips.IDLE,
}
## How far each hero's idle runs ahead of the first one's, in seconds: none of them breathes in step.
const IDLE_STAGGER_S: float = 0.7
## A full sway of the camera, in seconds, and how far it reaches from where it rests, in metres.
const SWAY_PERIOD_S: float = 30.0
const SWAY_REACH: Vector3 = Vector3(0.5, 0.12, 0.0)

var _time: float = 0.0
## The camera's pose as placed in the scene: the sway's centre.
var _camera_rest: Transform3D

@onready var _camera: Camera3D = $Camera
@onready var _heroes: Node3D = $Heroes


func _ready() -> void:
	_camera_rest = _camera.transform


func _process(delta: float) -> void:
	_time += delta
	var heroes: Array[Node] = _heroes.get_children()
	for i: int in heroes.size():
		var hero: CharacterRig = heroes[i]
		hero.pose(IDLES[hero.name], _time + i * IDLE_STAGGER_S)
	var phase: float = TAU * _time / SWAY_PERIOD_S
	var sway := Vector3(sin(phase) * SWAY_REACH.x, sin(phase * 2.0) * SWAY_REACH.y, 0.0)
	_camera.transform = _camera_rest.translated_local(sway)
