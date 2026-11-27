class_name Lookdev
extends Node3D
## The look-dev scene: the crypt kit, the hub corner, the vault and the effects, lit as the game will be, with every
## hero and skeleton posed, and the camera shots the look is judged from (`./uni tool lookdev --window --shots`, or the number keys when the
## scene runs on its own).
##
## It is where the look is decided before any gameplay exists: materials, lights, fog, glow and the camera's angle all
## show here first. Characters pose through the same CharacterRig.pose() the game's views use, so what looks right here
## looks right in play. A looping clip plays from the scene's clock; a one-shot holds the moment its pose names, so a
## shot always catches an attack mid-swing.
##
## The parity stage stands each of the crowd minion's clips (MinionCrowd) twice side by side, at the same time in it:
## the minion scene on the left, the baked crowd instance on the right, under one key light: the bake must look the
## same. At the row's ends stand two crowd instances in what only the crowd's shader shows: one flashing from a hit, one
## dying and sinking into the floor.
##
## The vault stage is the boss's level itself, its braziers' fires stood in by the stage's own (a brazier's view needs a
## session): a shot names how many burn, and the vault's ambient follows them by the game's own rule
## (Lighting.brazier_ambient_energy). The effects stage plays the game's Effects on a lit floor and holds them still
## (Effects.hold_at): every one-shot at FX_HELD of its life on one sheet, and the boss's slam beside a fireball's
## scorch on another.

## Where a shot is: the crypt (its braziers and torches), the hub (moonlit), the parity stage (its key light), the vault
## (its torches and as many of its braziers as the shot lights) or the effects stage (its key light).
enum Stage { CRYPT, HUB, PARITY, VAULT, FX }

## How far right of its rig a parity pair's crowd instance stands.
const PARITY_APART: float = 1.1
## The seconds since a parity instance was struck: never, so it doesn't flash (the rigs don't).
const NEVER_STRUCK: float = 1.0e6
## The two crowd instances at the row's ends: a walker just struck (its flash) and a minion late in its death (sinking).
const FLASHING_AT: Vector3 = Vector3(-6.6, 0, 0)
const SINKING_AT: Vector3 = Vector3(7.2, 0, 0)
const STRUCK_S: float = 0.05
const SINKING_S: float = 1.75
## The share of its life each effect on the effects stage is held at.
const FX_HELD: float = 0.4
## The effects sheet: its effects one a cell, FX_SHEET_COLUMNS a row, FX_SHEET_SPACING metres apart.
const FX_SHEET_COLUMNS: int = 5
const FX_SHEET_SPACING: float = 3.0
## The boss sheet (the stage's Boss effects): where the slam strikes and the fireball bursts.
const FX_SLAM_AT: Vector3 = Vector3(-2.5, 0, 0)
const FX_BLAST_AT: Vector3 = Vector3(3.5, 0, 1.0)

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
	&"VaultKnight": Pose.new(Clips.KNIGHT_SLASH, 0.45),
	&"VaultMage": Pose.new(Clips.MAGE_CAST, 0.0),
	&"VaultMinion": Pose.new(Clips.SKELETON_WALK, 0.2),
	&"VaultMinion2": Pose.new(Clips.SKELETON_ATTACK, 0.35),
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
## corridor, the heroes up close, the hoard and its braziers, the hub, the parity stage up close and from the game
## camera's angle, the vault from the game camera's range dark and with every brazier lit, and the effects held
## mid-life: every one-shot, and the boss's slam beside a fireball's scorch.
var shots: Array[Shot] = [
	Shot.new("crypt_wide", Vector3(3, 19, 16), Vector3(3, 0, 0), Stage.CRYPT, "crypt"),
	Shot.new("crypt_mid", Vector3(0.5, 14, 13), Vector3(0.5, 0, 0.5), Stage.CRYPT, "crypt"),
	Shot.new("crypt_close", Vector3(0, 9, 9.5), Vector3(0, 0.6, 1.5), Stage.CRYPT, "crypt"),
	Shot.new("crypt_corridor", Vector3(11.5, 12, 9), Vector3(11.5, 0, 0), Stage.CRYPT, "crypt"),
	Shot.new("heroes", Vector3(0, 3.6, 10.5), Vector3(0, 1.2, 2.4), Stage.CRYPT, "crypt"),
	Shot.new("hoard", Vector3(0, 4.5, 1.5), Vector3(0, 1.2, -4.5), Stage.CRYPT, "crypt"),
	Shot.new("hub", Vector3(0, 15, 14), Vector3(0, 0, -2.5), Stage.HUB, "hub"),
	Shot.new("crowd_parity", Vector3(0.3, 3.2, 14.5), Vector3(0.3, 0.9, 0), Stage.PARITY, "crypt"),
	Shot.new("crowd_parity_game", Vector3(0.3, 11, 11.5), Vector3(0.3, 0.6, 0), Stage.PARITY, "crypt"),
	Shot.new("vault_dark", Vector3(2, 21, 19), Vector3(2, 0, 4), Stage.VAULT, "vault", 0),
	Shot.new("vault_lit", Vector3(2, 21, 19), Vector3(2, 0, 4), Stage.VAULT, "vault", 4),
	Shot.new("fx_sheet", Vector3(0, 13, 12), Vector3(0, 0.6, 0.5), Stage.FX, "crypt"),
	Shot.new("fx_boss", Vector3(22.5, 12, 11), Vector3(22.5, 0, 0.5), Stage.FX, "crypt"),
]

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
@onready var _vault: Node3D = $VaultStage
@onready var _vault_fires: Node3D = $VaultStage/Fires
@onready var _fx: Node3D = $FxStage
@onready var _fx_key: DirectionalLight3D = $FxStage/Key
@onready var _fx_sheet: Effects = $FxStage/Sheet
@onready var _fx_boss: Effects = $FxStage/Boss
@onready var _crowd_clips: UnifiedCrowdClips = load(MinionCrowd.TABLE)


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


## Puts the camera at shot `index` and lights its stage under the shot's environment: the hub's moon, the parity or
## effects stage's key light, the vault's fires the shot lights (its ambient following them), or the crypt's. An
## effects shot plays its sheet's effects anew and holds them.
func show_shot(index: int) -> void:
	var shot: Shot = shots[index]
	var stages: Dictionary[Stage, Node3D] = {Stage.HUB: _hub, Stage.PARITY: _parity, Stage.VAULT: _vault, Stage.FX: _fx}
	var offset: Vector3 = stages[shot.stage].position if stages.has(shot.stage) else Vector3.ZERO
	_camera.look_at_from_position(shot.eye + offset, shot.target + offset)
	var environment: Environment = load("res://game/environments/%s.tres" % shot.environment)
	_moon.visible = shot.stage == Stage.HUB
	_parity_key.visible = shot.stage == Stage.PARITY
	_fx_key.visible = shot.stage == Stage.FX
	if shot.stage == Stage.VAULT:
		var total: int = _vault_fires.get_child_count()
		for fire: int in total:
			(_vault_fires.get_child(fire) as Node3D).visible = fire < shot.fires
		environment = environment.duplicate()
		environment.ambient_light_energy = Lighting.brazier_ambient_energy(environment, shot.fires, total)
	_environment.environment = environment
	if shot.shot_name == "fx_sheet":
		_show_fx_sheet()
	elif shot.shot_name == "fx_boss":
		_show_fx_boss()


## Every one-shot kind, a tracer, the shock ring and a fireball's flash on a grid, held at FX_HELD of their lives.
func _show_fx_sheet() -> void:
	_fx_sheet.clear()
	var origin: Vector3 = _fx_sheet.global_position
	var cell: int = 0
	for kind: Effects.Kind in Effects.Kind.values():
		_fx_sheet.play(kind, origin + _fx_cell(cell) + Vector3(0, 1.0, 0))
		cell += 1
	var at: Vector3 = origin + _fx_cell(cell)
	_fx_sheet.tracer(at + Vector3(-1.2, 1.2, 0.4), at + Vector3(1.2, 1.2, -0.4))
	_fx_sheet.shock_ring(origin + _fx_cell(cell + 1))
	_fx_sheet.pulse(origin + _fx_cell(cell + 2) + Vector3(0, Effects.FLASH_HEIGHT, 0), Effects.FIREBALL_FLASH,
		Effects.FIREBALL_FLASH_ENERGY, Effects.FIREBALL_FLASH_RANGE, Effects.FIREBALL_FLASH_S, 0)
	_fx_sheet.hold_at(FX_HELD)


## The boss's slam (its shock ring, the dust on its rim, its crack) beside what a fireball's blast leaves (its smoke,
## flash and scorch: its burst, on the other sheet, would hide the scorch), held at FX_HELD of their lives.
func _show_fx_boss() -> void:
	_fx_boss.clear()
	var slam: Vector3 = _fx_boss.global_position + FX_SLAM_AT
	_fx_boss.shock_ring(slam)
	_fx_boss.play(Effects.Kind.SLAM_DUST, slam)
	_fx_boss.crack(slam, 0)
	var blast: Vector3 = _fx_boss.global_position + FX_BLAST_AT
	_fx_boss.play(Effects.Kind.SMOKE, blast)
	_fx_boss.pulse(blast + Vector3(0, Effects.FLASH_HEIGHT, 0), Effects.FIREBALL_FLASH, Effects.FIREBALL_FLASH_ENERGY,
		Effects.FIREBALL_FLASH_RANGE, Effects.FIREBALL_FLASH_S, 0)
	_fx_boss.scorch(blast, 0)
	_fx_boss.hold_at(FX_HELD)


## Where the effects sheet's cell `cell` stands, from the sheet's middle: FX_SHEET_COLUMNS a row, from the far row.
func _fx_cell(cell: int) -> Vector3:
	@warning_ignore("integer_division")
	var row: int = cell / FX_SHEET_COLUMNS
	var column: int = cell % FX_SHEET_COLUMNS
	return Vector3((column - (FX_SHEET_COLUMNS - 1) / 2.0) * FX_SHEET_SPACING, 0, (row - 1) * FX_SHEET_SPACING)


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


## A camera shot: where the camera stands and what it looks at (in its stage's space), its stage, its environment (a
## file's name in game/environments/), and in the vault how many of its braziers burn.
class Shot:
	var shot_name: String
	var eye: Vector3
	var target: Vector3
	var stage: Stage
	var environment: String
	var fires: int

	func _init(named: String, from: Vector3, looking_at: Vector3, on_stage: Stage, lit_by: String, burning: int = 0) -> void:
		shot_name = named
		eye = from
		target = looking_at
		stage = on_stage
		environment = lit_by
		fires = burning
