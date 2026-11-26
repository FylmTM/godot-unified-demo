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
##
## The parity stage stands each of the crowd minion's clips (MinionCrowd) twice side by side, at the same time in it:
## the minion scene on the left, the baked crowd instance on the right, under one key light: the bake must look the
## same. Behind them stand two crowd instances in what only the crowd's shader shows: one flashing from a hit, one dying
## and sinking into the floor.

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

## Each parity pair's pose, by its rig's order under ParityStage/Rigs: one for each of MinionCrowd's clips, a
## one-shot mid-action, the walk between two baked frames (the shader's blend shows).
var parity: Array[Pose] = [
	Pose.new(Clips.SKELETON_IDLE, 0.5),
	Pose.new(Clips.SKELETON_WALK, 0.42),
	Pose.new(Clips.SKELETON_ATTACK, 0.45),
	Pose.new(Clips.SKELETON_RISE, 1.1),
	Pose.new(Clips.SKELETON_DEATH, 0.8),
]

## The shots, in the order the tool takes them: the crypt from the game camera's range (wide, mid, close), its
## corridor, the heroes up close, the hoard and its braziers, the hub, and the parity stage up close and from the game
## camera's angle.
var shots: Array[Shot] = [
	Shot.new("crypt_wide", Vector3(3, 19, 16), Vector3(3, 0, 0), Stage.CRYPT),
	Shot.new("crypt_mid", Vector3(0.5, 14, 13), Vector3(0.5, 0, 0.5), Stage.CRYPT),
	Shot.new("crypt_close", Vector3(0, 9, 9.5), Vector3(0, 0.6, 1.5), Stage.CRYPT),
	Shot.new("crypt_corridor", Vector3(11.5, 12, 9), Vector3(11.5, 0, 0), Stage.CRYPT),
	Shot.new("heroes", Vector3(0, 3.6, 10.5), Vector3(0, 1.2, 2.4), Stage.CRYPT),
	Shot.new("hoard", Vector3(0, 4.5, 1.5), Vector3(0, 1.2, -4.5), Stage.CRYPT),
	Shot.new("hub", Vector3(0, 15, 14), Vector3(0, 0, -2.5), Stage.HUB),
	Shot.new("crowd_parity", Vector3(0.5, 2.8, 12), Vector3(0.5, 0.9, 0), Stage.PARITY),
	Shot.new("crowd_parity_game", Vector3(0.5, 9, 9.5), Vector3(0.5, 0.6, 0), Stage.PARITY),
]

## Where a shot is: the crypt (its braziers and torches), the hub (moonlit) or the parity stage (its key light).
enum Stage { CRYPT, HUB, PARITY }

## How far right of its rig a parity pair's crowd instance stands.
const PARITY_APART: float = 1.1
## The seconds since a parity instance was struck: never, so it doesn't flash (the rigs don't).
const NEVER_STRUCK: float = 1.0e6
## The two crowd instances behind the pairs: a walker just struck (its flash) and a minion late in its death (sinking).
const FLASHING_AT: Vector3 = Vector3(-1.2, 0, -2.2)
const SINKING_AT: Vector3 = Vector3(1.2, 0, -2.2)
const STRUCK_S: float = 0.05
const SINKING_S: float = 1.75

var _time: float = 0.0
var _idle: Pose = Pose.new(Clips.IDLE, 0.0)

@onready var _camera: Camera3D = $Camera
@onready var _environment: WorldEnvironment = $WorldEnvironment
@onready var _cast: Node3D = $Cast
@onready var _hub: Node3D = $HubStage
@onready var _moon: DirectionalLight3D = $HubStage/Moon
@onready var _parity: Node3D = $ParityStage
@onready var _parity_key: DirectionalLight3D = $ParityStage/Key
@onready var _parity_rigs: Node3D = $ParityStage/Rigs
@onready var _parity_crowd: MultiMeshInstance3D = $ParityStage/Crowd
@onready var _crowd_clips: CrowdClips = load(MinionCrowd.TABLE)


func _ready() -> void:
	var crowd := MultiMesh.new()
	crowd.transform_format = MultiMesh.TRANSFORM_3D
	crowd.use_custom_data = true
	crowd.mesh = load(MinionCrowd.MESH)
	var pairs: int = _parity_rigs.get_child_count()
	crowd.instance_count = pairs + 2
	for index: int in pairs:
		var rig: Node3D = _parity_rigs.get_child(index)
		crowd.set_instance_transform(index, rig.transform.translated(Vector3(PARITY_APART, 0, 0)))
	crowd.set_instance_transform(pairs, Transform3D(Basis.IDENTITY, FLASHING_AT))
	crowd.set_instance_transform(pairs + 1, Transform3D(Basis.IDENTITY, SINKING_AT))
	_parity_crowd.multimesh = crowd
	_parity_crowd.material_override = MinionCrowd.material()
	show_shot(0)


func _process(delta: float) -> void:
	_time += delta
	pose_cast(_time)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key.pressed and key.keycode >= KEY_1 and key.keycode < KEY_1 + shots.size():
		show_shot(key.keycode - KEY_1)


## Poses every cast member at `seconds` on the scene's clock: a looping clip plays on from its pose's start, a one-shot
## holds the moment its pose names. A member without a pose idles. Each parity pair takes its pose the same way, the rig
## through pose() and the crowd instance through its custom data.
func pose_cast(seconds: float) -> void:
	for member: Node in _cast.get_children():
		var pose: Pose = poses.get(member.name, _idle)
		(member as CharacterRig).pose(pose.clip, pose.at(seconds))
	for index: int in parity.size():
		var pose: Pose = parity[index]
		(_parity_rigs.get_child(index) as CharacterRig).pose(pose.clip, pose.at(seconds))
		var clip: float = _crowd_clips.index(pose.clip)
		_parity_crowd.multimesh.set_instance_custom_data(index, Color(clip, pose.at(seconds), NEVER_STRUCK, 0))
	var walk: float = MinionCrowd.Clip.WALK
	var death: float = MinionCrowd.Clip.DEATH
	_parity_crowd.multimesh.set_instance_custom_data(parity.size(), Color(walk, seconds, STRUCK_S, 0))
	_parity_crowd.multimesh.set_instance_custom_data(parity.size() + 1, Color(death, SINKING_S, NEVER_STRUCK, 0))


## Puts the camera at shot `index` and lights its stage: the hub's moon and environment, the parity stage's key light,
## or the crypt's.
func show_shot(index: int) -> void:
	var shot: Shot = shots[index]
	var offset: Vector3 = Vector3.ZERO
	if shot.stage == Stage.HUB:
		offset = _hub.position
	elif shot.stage == Stage.PARITY:
		offset = _parity.position
	_camera.look_at_from_position(shot.eye + offset, shot.target + offset)
	_environment.environment = load("res://game/environments/%s.tres" % ("hub" if shot.stage == Stage.HUB else "crypt"))
	_moon.visible = shot.stage == Stage.HUB
	_parity_key.visible = shot.stage == Stage.PARITY


## A cast member's pose: a clip, and the time in it a one-shot holds (or a loop starts from).
class Pose:
	var clip: StringName
	var seconds: float

	func _init(clip_name: StringName, at_seconds: float) -> void:
		clip = clip_name
		seconds = at_seconds

	## The time in its clip at `scene_seconds` on the scene's clock: a loop plays on from `seconds`, a one-shot holds it.
	func at(scene_seconds: float) -> float:
		return seconds + (scene_seconds if clip in Clips.LOOPING else 0.0)


## A camera shot: where the camera stands and what it looks at (in its stage's space), and its stage.
class Shot:
	var shot_name: String
	var eye: Vector3
	var target: Vector3
	var stage: Stage

	func _init(named: String, from: Vector3, looking_at: Vector3, on_stage: Stage) -> void:
		shot_name = named
		eye = from
		target = looking_at
		stage = on_stage
