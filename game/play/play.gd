class_name Play
extends Node3D
## The play scene: the session, the level root it instances the floor under (its meshes are the crypt), the views
## root it spawns the heroes under, the bolts' MultiMesh, the local players' devices (Couch), the camera, the effects,
## the crypt's environment and the HUD. It turns the sim's events into effects as soon as they are predicted (EMITTED):
## sparks on a hit, a bolt's burst, a crossbow's tracer, dust where a prop lands hard, and a shake when a local hero is
## hurt.
##
## The mouse's aim reaches the sim through it, as only a script knows it: just before the session samples (its
## input_wanted, so this frame's sample takes it), the cursor's ray meets a plane at chest height, and the direction
## from the keyboard player's shown hero to that point is that player's input value. Esc, or a pad's Start that the
## Couch left (a pad that plays already), pauses or resumes the game for everyone.

## The height of the plane the cursor aims on: a hero's chest, so the hero looks at what the cursor is over.
const AIM_PLANE_HEIGHT: float = 1.2
## A cursor this close to the hero (metres, on the floor) doesn't aim: its direction would swing wildly.
const AIM_DEAD_RADIUS: float = 0.5
## Where on a skeleton its hit's sparks fly from, above its feet.
const HIT_HEIGHT: float = 1.1
## A prop landing faster than this (metres per second) raises dust.
const DUST_SPEED: float = 5.0
## How hard a local hero's hurt shakes the camera (0 to 1).
const HURT_SHAKE: float = 0.5

## Whether the mouse aims for the keyboard's player: once it has moved.
var _mouse_aims: bool = false

@onready var _session: UnifiedSession = $UnifiedSession
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _effects: Effects = $Effects
@onready var _level: Node3D = $Level
@onready var _views: Node3D = $Views


func _ready() -> void:
	_session.level_root = _level
	_session.view_root = _views
	_session.level_changed.connect(_on_level_changed)
	_session.input_wanted.connect(_set_aims)
	_session.sim_event.connect(_on_sim_event)
	if not _session.running:
		_session.start_single()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_aims = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		var pause := CommandSetPaused.new()
		pause.paused = not Unified.data.hud.paused
		_session.send_command(pause)
		get_viewport().set_input_as_handled()


## Every local player's mouse aim, for this frame's sample: toward the cursor for the one who holds the keyboard (or
## every device), none for the others, and none while game input is off.
func _set_aims() -> void:
	for local: int in _session.get_local_indices():
		var device: int = _session.get_local_device(local)
		var keyboard: bool = device == UnifiedSession.DEVICE_KEYBOARD or device == UnifiedSession.DEVICE_ANY
		var aims: bool = keyboard and _mouse_aims and _session.game_input
		Unified.local_input(local).aim = _cursor_aim(local) if aims else Vector2.ZERO


## From local player `local`'s shown hero to where the cursor's ray meets the aim plane, on the floor (x, z); zero
## without a hero, without a hit, or within AIM_DEAD_RADIUS of the hero.
func _cursor_aim(local: int) -> Vector2:
	var hero: Node3D = _session.get_player_view(EnumView.HERO, _session.get_local_player_key(local)) as Node3D
	var camera: Camera3D = get_viewport().get_camera_3d()
	if hero == null or camera == null:
		return Vector2.ZERO
	var cursor: Vector2 = get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, AIM_PLANE_HEIGHT)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
	if hit == null:
		return Vector2.ZERO
	var point: Vector3 = hit
	var aim := Vector2(point.x - hero.global_position.x, point.z - hero.global_position.z)
	return aim if aim.length() >= AIM_DEAD_RADIUS else Vector2.ZERO


## The floor is on screen: the camera frames its hero spawns until a local hero is there.
func _on_level_changed(_level_id: int) -> void:
	var sum := Vector3.ZERO
	var count: int = 0
	for marker: Node in Unified.level_markers(_level):
		if marker is HeroSpawn:
			sum += (marker as HeroSpawn).global_position
			count += 1
	if count > 0:
		_camera_rig.fallback = sum / count


## The effects of the sim's events, on their first showing (EMITTED).
func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state != UnifiedSession.EVENT_EMITTED:
		return
	if event is EventMinionHit:
		_effects.sparks((event as EventMinionHit).position + Vector3(0, HIT_HEIGHT, 0))
	elif event is EventBoltBurst:
		_effects.burst((event as EventBoltBurst).position)
	elif event is EventCrossbowShot:
		var shot := event as EventCrossbowShot
		_effects.tracer(shot.from, shot.to)
	elif event is EventPropImpact:
		var impact := event as EventPropImpact
		if impact.speed >= DUST_SPEED:
			_effects.dust(impact.position)
	elif event is EventHeroHurt:
		if _session.get_local_index((event as EventHeroHurt).player) >= 0:
			_camera_rig.shake(HURT_SHAKE)
