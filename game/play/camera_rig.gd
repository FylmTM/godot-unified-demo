class_name CameraRig
extends Node3D
## The one shared camera: a fixed 3/4 view from the south (it looks toward -Z and never turns, so the sim's world axes
## are the screen's), framing every local hero, so couch co-op needs no split screen.
##
## The rig stands at the middle of the local heroes' shown positions, and its camera pulls back as they spread apart,
## within limits. It follows with exponential smoothing, so it eases rather than jitters, and cuts where the goal jumps
## further than smoothing should cross (the first frame, a hero arriving across the floor). With no local hero yet it
## frames `fallback`. A shake (a local hero hurt) jolts the camera by smooth noise that dies away.
##
## Its focus never sinks below the walking surface (y = 0 on every floor: docs/ART.md): heroes below it ride the
## lift down its shaft, and a focus following them would put the floor's edge between the camera and the party. Held at
## the rim, the camera pitches down toward PITCH_DEEP_DEG as they go deeper, so it looks into the shaft at the deck.
##
## The world's sounds are heard from the rig, not the camera: its Listener (the current AudioListener3D) stands at the
## focus on the floor, among the heroes, turned with the camera's yaw, so a sound pans by where it is on the screen and
## fades by how far it is from the party, not from a camera many metres up.

## The camera's angle down from the horizon, and the steepest it pitches to look down a shaft at heroes DEEP_AT metres
## or more below the walking surface.
const PITCH_DEG: float = 55.0
const PITCH_DEEP_DEG: float = 75.0
const DEEP_AT: float = 2.0
## The walking surface's height on every floor: the focus never goes below it.
const WALK_HEIGHT: float = 0.0
## The camera's distance from the focus with the heroes together, and the most it pulls back.
const DISTANCE_MIN: float = 18.0
const DISTANCE_MAX: float = 28.0
## Metres the camera pulls back for each metre the farthest local hero stands from their middle.
const ZOOM_PER_SPREAD: float = 1.2
## The height above the floor the camera looks at: the heroes' middle, not their feet.
const FOCUS_HEIGHT: float = 1.0
## How fast the rig closes on its goal, per second (exponential).
const FOLLOW_RATE: float = 5.0
## A goal farther than this from the rig is cut to, not eased to.
const CUT_DISTANCE: float = 12.0
## The most a full shake moves the camera (metres), and how fast a shake dies away (its amount per second).
const SHAKE_MAX: float = 0.35
const SHAKE_DECAY: float = 2.5

## How far toward the screen's bottom (+Z, metres on the floor) the rig looks past the heroes' middle, so they show
## higher on the screen, while the boon panels cover the bottom of the screen (bottom_covered).
const PANEL_SHIFT: float = 4.0

## Where the rig looks with no local hero (the play scene sets the floor's hero spawns' middle).
var fallback: Vector3 = Vector3.ZERO
## Whether something covers the screen's bottom (the boon panels): the rig looks PANEL_SHIFT past the heroes.
var bottom_covered: bool = false

var _distance: float = DISTANCE_MIN
var _framed: bool = false
## How far below the walking surface the local heroes' middle is (0: on it): the pitch steepens with it.
var _depth: float = 0.0
var _pitch: float = deg_to_rad(PITCH_DEG)
var _shake: float = 0.0
var _shake_time: float = 0.0

@onready var _camera: Camera3D = $Camera3D
@onready var _listener: AudioListener3D = $Listener


func _ready() -> void:
	_listener.make_current()


func _process(delta: float) -> void:
	var goal: Vector3 = fallback
	var spread: float = 0.0
	var heroes: Array[Node3D] = _local_heroes()
	if not heroes.is_empty():
		goal = Vector3.ZERO
		for hero: Node3D in heroes:
			goal += hero.global_position
		goal /= heroes.size()
		for hero: Node3D in heroes:
			spread = maxf(spread, Vector2(hero.global_position.x - goal.x, hero.global_position.z - goal.z).length())
	_depth = maxf(WALK_HEIGHT - goal.y, 0.0)
	goal.y = maxf(goal.y, WALK_HEIGHT)
	if bottom_covered:
		goal.z += PANEL_SHIFT
	var distance: float = clampf(DISTANCE_MIN + spread * ZOOM_PER_SPREAD, DISTANCE_MIN, DISTANCE_MAX)
	if not _framed or global_position.distance_to(goal) > CUT_DISTANCE:
		global_position = goal
		_distance = distance
		_framed = true
	else:
		var weight: float = 1.0 - exp(-FOLLOW_RATE * delta)
		global_position = global_position.lerp(goal, weight)
		_distance = lerpf(_distance, distance, weight)
	var steep: float = clampf(_depth / DEEP_AT, 0.0, 1.0)
	var pitch_goal: float = deg_to_rad(lerpf(PITCH_DEG, PITCH_DEEP_DEG, steep))
	_pitch = lerpf(_pitch, pitch_goal, 1.0 - exp(-FOLLOW_RATE * delta))
	var pitch: float = _pitch
	var focus := Vector3(0, FOCUS_HEIGHT, 0)
	_shake = maxf(_shake - SHAKE_DECAY * delta, 0.0)
	_shake_time += delta
	var t: float = _shake_time
	var jolt := Vector3(sin(t * 47.0), sin(t * 39.0 + 1.3), sin(t * 53.0 + 2.1)) * (_shake * _shake * SHAKE_MAX)
	_camera.position = focus + Vector3(0, sin(pitch), cos(pitch)) * _distance + jolt
	_camera.look_at(global_position + focus + jolt * 0.5, Vector3.UP)
	_listener.global_basis = Basis(Vector3.UP, _camera.global_rotation.y)


## Jolts the camera by `amount` (0 to 1; a stronger shake than the one running replaces it).
func shake(amount: float) -> void:
	_shake = maxf(_shake, clampf(amount, 0.0, 1.0))


## The views of this machine's heroes that are in the scene.
func _local_heroes() -> Array[Node3D]:
	var heroes: Array[Node3D] = []
	for player: int in Unified.session.local_players:
		var hero: Node3D = Unified.session.get_player_view(EnumView.HERO, player) as Node3D
		if hero != null:
			heroes.append(hero)
	return heroes
