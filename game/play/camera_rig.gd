class_name CameraRig
extends Node3D
## The one shared camera: a fixed 3/4 view from the south (it looks toward -Z and never turns, so the sim's world axes
## are the screen's), framing every local hero, so couch co-op needs no split screen.
##
## The rig stands at the middle of the local heroes' shown positions, and its camera pulls back as they spread apart,
## within limits. It follows with exponential smoothing, so it eases rather than jitters, and cuts where the goal jumps
## further than smoothing should cross (the first frame, a hero arriving across the floor). With no local hero yet it
## frames `fallback`. A shake (a local hero hurt) jolts the camera by smooth noise that dies away.

## The camera's angle down from the horizon.
const PITCH_DEG: float = 55.0
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

## Where the rig looks with no local hero (the play scene sets the floor's hero spawns' middle).
var fallback: Vector3 = Vector3.ZERO

var _distance: float = DISTANCE_MIN
var _framed: bool = false
var _shake: float = 0.0
var _shake_time: float = 0.0

@onready var _camera: Camera3D = $Camera3D


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
	var distance: float = clampf(DISTANCE_MIN + spread * ZOOM_PER_SPREAD, DISTANCE_MIN, DISTANCE_MAX)
	if not _framed or global_position.distance_to(goal) > CUT_DISTANCE:
		global_position = goal
		_distance = distance
		_framed = true
	else:
		var weight: float = 1.0 - exp(-FOLLOW_RATE * delta)
		global_position = global_position.lerp(goal, weight)
		_distance = lerpf(_distance, distance, weight)
	var pitch: float = deg_to_rad(PITCH_DEG)
	var focus := Vector3(0, FOCUS_HEIGHT, 0)
	_shake = maxf(_shake - SHAKE_DECAY * delta, 0.0)
	_shake_time += delta
	var t: float = _shake_time
	var jolt := Vector3(sin(t * 47.0), sin(t * 39.0 + 1.3), sin(t * 53.0 + 2.1)) * (_shake * _shake * SHAKE_MAX)
	_camera.position = focus + Vector3(0, sin(pitch), cos(pitch)) * _distance + jolt
	_camera.look_at(global_position + focus + jolt * 0.5, Vector3.UP)


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
