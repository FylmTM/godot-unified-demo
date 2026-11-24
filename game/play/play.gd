class_name Play
extends Node3D
## The play scene: the session, the level root it instances the floor under (the floor's meshes are the crypt; its
## markers hide themselves), the views root it spawns the heroes under, the camera, the crypt's environment and the
## HUD.
##
## Two things only a script knows reach the sim through it. The mouse's aim: just before the session samples (its
## input_wanted, so this frame's sample takes it), the cursor's ray meets a plane at chest height, and the direction
## from the local hero's shown position to that point is the keyboard player's input value. And couch co-op: a pad
## that presses Start joins as another local player; the first player keeps the keyboard and mouse.

## The height of the plane the cursor aims on: a hero's chest, so the hero looks at what the cursor is over.
const AIM_PLANE_HEIGHT: float = 1.2

## Whether the mouse aims for the keyboard's player: once it moves, until a stick shared with it aims instead.
var _mouse_aims: bool = false

@onready var session: UnifiedSession = %UnifiedSession
@onready var camera_rig: CameraRig = $CameraRig
@onready var _level: Node3D = $Level
@onready var _views: Node3D = $Views


func _ready() -> void:
	session.level_root = _level
	session.view_root = _views
	session.level_changed.connect(_on_level_changed)
	session.input_wanted.connect(_set_aim)
	if not session.running:
		session.start_single()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_aims = true


## A pad's Start joins it as another local player, unless it plays already; Esc, or a playing pad's Start, pauses or
## resumes the game for everyone (the co-op pause).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"join") and _join(event.device):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause"):
		var pause := CommandSetPaused.new()
		pause.paused = not Unified.data.hud.paused
		session.send_command(pause)
		get_viewport().set_input_as_handled()


## Joins the pad `device` as another local player; false when it plays already or the session refuses it.
func _join(device: int) -> bool:
	for local: int in session.get_local_indices():
		if session.get_local_device(local) == device:
			return false
	if session.get_local_indices().size() == 1 and session.get_local_device(0) == UnifiedSession.DEVICE_ANY:
		session.set_local_device(0, UnifiedSession.DEVICE_KEYBOARD)
	return session.add_local_player(device, "Pad %d" % (device + 1)) >= 0


## The keyboard player's aim, for this frame's sample: toward the cursor, or none (the hero faces its move).
func _set_aim() -> void:
	var stick: Vector2 = Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	if stick != Vector2.ZERO and session.get_local_device(0) == UnifiedSession.DEVICE_ANY:
		_mouse_aims = false
	Unified.input.aim = _cursor_aim() if _mouse_aims else Vector2.ZERO


## From the local hero's shown position to where the cursor's ray meets the aim plane, on the floor (x, z); zero
## without a hero or a hit.
func _cursor_aim() -> Vector2:
	var hero: Node3D = session.get_player_view(EnumView.HERO, session.local_player) as Node3D
	var camera: Camera3D = get_viewport().get_camera_3d()
	if hero == null or camera == null:
		return Vector2.ZERO
	var cursor: Vector2 = get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, AIM_PLANE_HEIGHT)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
	if hit == null:
		return Vector2.ZERO
	var point: Vector3 = hit
	return Vector2(point.x - hero.global_position.x, point.z - hero.global_position.z)


## The floor is on screen: the camera frames its hero spawns until a local hero is there.
func _on_level_changed(_level_id: int) -> void:
	var sum := Vector3.ZERO
	var count: int = 0
	for marker: Node in Unified.level_markers(_level):
		if marker is HeroSpawn:
			sum += (marker as HeroSpawn).global_position
			count += 1
	if count > 0:
		camera_rig.fallback = sum / count
