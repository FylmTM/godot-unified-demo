class_name Lookdev
extends Node3D
## The look-dev scene: the crypt kit and the hub corner, lit as the game will be, with every hero and skeleton posed,
## and the camera shots the look is judged from (`./uni tool lookdev --window --shots`, or the number keys when the
## scene runs on its own).
##
## It is where the look is decided before any gameplay exists: materials, lights, fog, glow and the camera's angle all
## show here first. Characters pose through the same CharacterRig.pose() the game's views use, so what looks right here
## looks right in play. A looping clip plays from the scene's clock; a one-shot holds the moment its pose names, so a
## shot always catches an attack mid-swing.

## Each cast member's pose, by node name under Cast; a member without one idles.
var poses: Dictionary[StringName, Pose] = {
	&"Knight": Pose.new(Clips.KNIGHT_SLASH, 0.45),
	&"Barbarian": Pose.new(Clips.BARBARIAN_CLEAVE, 0.4),
	&"Mage": Pose.new(Clips.MAGE_CAST, 0.0),
	&"Rogue": Pose.new(Clips.ROGUE_AIM, 2.0),
	&"Minion": Pose.new(Clips.SKELETON_WALK, 0.0),
	&"Minion2": Pose.new(Clips.SKELETON_WALK, 0.4),
	&"Minion3": Pose.new(Clips.SKELETON_ATTACK, 0.35),
	&"Minion4": Pose.new(Clips.SKELETON_RISE, 1.1),
	&"Warrior": Pose.new(Clips.SKELETON_IDLE, 0.0),
	&"SkeletonRogue": Pose.new(Clips.SKELETON_WALK, 0.7),
	&"SkeletonMage": Pose.new(Clips.MAGE_CAST, 0.3),
	&"HubMage": Pose.new(Clips.IDLE_ALT, 0.5),
}

## The shots, in the order the tool takes them: the crypt from the game camera's range (wide, mid, close), its
## corridor, the heroes up close, the hoard and its braziers, and the hub.
var shots: Array[Shot] = [
	Shot.new("crypt_wide", Vector3(3, 19, 16), Vector3(3, 0, 0), false),
	Shot.new("crypt_mid", Vector3(0.5, 14, 13), Vector3(0.5, 0, 0.5), false),
	Shot.new("crypt_close", Vector3(0, 9, 9.5), Vector3(0, 0.6, 1.5), false),
	Shot.new("crypt_corridor", Vector3(11.5, 12, 9), Vector3(11.5, 0, 0), false),
	Shot.new("heroes", Vector3(0, 3.6, 10.5), Vector3(0, 1.2, 2.4), false),
	Shot.new("hoard", Vector3(0, 4.5, 1.5), Vector3(0, 1.2, -4.5), false),
	Shot.new("hub", Vector3(0, 15, 14), Vector3(0, 0, -2.5), true),
]

var _time: float = 0.0
var _idle: Pose = Pose.new(Clips.IDLE, 0.0)

@onready var _camera: Camera3D = $Camera
@onready var _environment: WorldEnvironment = $WorldEnvironment
@onready var _cast: Node3D = $Cast
@onready var _hub: Node3D = $HubStage
@onready var _moon: DirectionalLight3D = $HubStage/Moon


func _ready() -> void:
	show_shot(0)


func _process(delta: float) -> void:
	_time += delta
	pose_cast(_time)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key.pressed and key.keycode >= KEY_1 and key.keycode < KEY_1 + shots.size():
		show_shot(key.keycode - KEY_1)


## Poses every cast member at `seconds` on the scene's clock: a looping clip plays on from its pose's start, a one-shot
## holds the moment its pose names. A member without a pose idles.
func pose_cast(seconds: float) -> void:
	for member: Node in _cast.get_children():
		var pose: Pose = poses.get(member.name, _idle)
		var looping: bool = pose.clip in Clips.LOOPING
		(member as CharacterRig).pose(pose.clip, pose.seconds + (seconds if looping else 0.0))


## Puts the camera at shot `index` and lights its stage: the hub's moon and environment, or the crypt's.
func show_shot(index: int) -> void:
	var shot: Shot = shots[index]
	var offset: Vector3 = _hub.position if shot.hub else Vector3.ZERO
	_camera.look_at_from_position(shot.eye + offset, shot.target + offset)
	_environment.environment = load("res://game/environments/%s.tres" % ("hub" if shot.hub else "crypt"))
	_moon.visible = shot.hub


## A cast member's pose: a clip, and the time in it a one-shot holds (or a loop starts from).
class Pose:
	var clip: StringName
	var seconds: float

	func _init(clip_name: StringName, at_seconds: float) -> void:
		clip = clip_name
		seconds = at_seconds


## A camera shot: where the camera stands and what it looks at (in its stage's space), and whether it is the hub's.
class Shot:
	var shot_name: String
	var eye: Vector3
	var target: Vector3
	var hub: bool

	func _init(named: String, from: Vector3, looking_at: Vector3, in_hub: bool) -> void:
		shot_name = named
		eye = from
		target = looking_at
		hub = in_hub
