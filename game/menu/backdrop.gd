class_name Backdrop
extends Node3D
## The menus' backdrop: the crew at the graveyard's gate on a moonlit night, built from the hub kit's parts (not the
## hub a run will start in: nothing here plays), lit as docs/ART.md lights the hub.
##
## The four heroes idle on their own clock, each a little out of step with the others, through the same
## CharacterRig.pose() the game's views use. On hero select, a hero someone picks steps forward and takes its class's
## stance (feature()). The camera sways slowly around where it was placed, so the screen is alive without drawing the
## eye from the menu on its left.

## Each hero's idle, by its node's name under Heroes.
const IDLES: Dictionary[StringName, StringName] = {
	&"Knight": Clips.IDLE,
	&"Barbarian": Clips.BARBARIAN_IDLE,
	&"Mage": Clips.IDLE_ALT,
	&"Rogue": Clips.IDLE,
}
## Each hero's stance once a seat picks it.
const STANCES: Dictionary[StringName, StringName] = {
	&"Knight": Clips.KNIGHT_BLOCK,
	&"Barbarian": Clips.BARBARIAN_CLEAVE,
	&"Mage": Clips.MAGE_CAST,
	&"Rogue": Clips.ROGUE_AIM,
}
## How far a picked hero steps forward (metres, toward the camera) and how fast it gets there (per second).
const STEP_FORWARD: float = 1.2
const STEP_RATE: float = 6.0
## How far each hero's idle runs ahead of the first one's, in seconds: none of them breathes in step.
const IDLE_STAGGER_S: float = 0.7
## A full sway of the camera, in seconds, and how far it reaches from where it rests, in metres.
const SWAY_PERIOD_S: float = 30.0
const SWAY_REACH: Vector3 = Vector3(0.5, 0.12, 0.0)

var _time: float = 0.0
## The camera's pose as placed in the scene: the sway's centre.
var _camera_rest: Transform3D
## The heroes, in the order they stand, and each one's idle.
var _rigs: Array[CharacterRig] = []
var _idles: Array[StringName] = []
## Each hero's place as set in the scene, and when a seat picked it (-1: no seat has).
var _rests: Array[Vector3] = []
var _picked_at: Array[float] = []

@onready var _camera: Camera3D = $Camera


func _ready() -> void:
	_camera_rest = _camera.transform
	for hero: Node in $Heroes.get_children():
		_rigs.append(hero as CharacterRig)
		_idles.append(IDLES[hero.name])
		_rests.append((hero as Node3D).position)
		_picked_at.append(-1.0)


func _process(delta: float) -> void:
	_time += delta
	for i: int in _rigs.size():
		var picked: bool = _picked_at[i] >= 0.0
		if picked:
			_rigs[i].pose(STANCES[_rigs[i].name], _time - _picked_at[i])
		else:
			_rigs[i].pose(_idles[i], _time + i * IDLE_STAGGER_S)
		var goal: Vector3 = _rests[i] + Vector3(0, 0, STEP_FORWARD if picked else 0.0)
		_rigs[i].position = _rigs[i].position.lerp(goal, minf(1.0, STEP_RATE * delta))
	var phase: float = TAU * _time / SWAY_PERIOD_S
	var sway := Vector3(sin(phase) * SWAY_REACH.x, sin(phase * 2.0) * SWAY_REACH.y, 0.0)
	_camera.transform = _camera_rest.translated_local(sway)


## Steps forward the heroes of `picks` (EnumClass, the seats' picks; Any picks nobody), and back the others.
func feature(picks: Array[int]) -> void:
	for i: int in _rigs.size():
		var picked: bool = false
		for pick: int in picks:
			picked = picked or Heroes.name_of(pick) == String(_rigs[i].name)
		if picked and _picked_at[i] < 0.0:
			_picked_at[i] = _time
		elif not picked:
			_picked_at[i] = -1.0
