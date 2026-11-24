class_name MinionView
extends Node3D
## A skeleton minion's view (View_Minion, simulation/extension/frame.odin): the host poses this root at the minion's
## feet, turned to its facing, and the script animates the skeleton from the minion's phase and when it began, on the
## session's shown time: it climbs out of the floor (Rise), stands (Idle, asleep in a pack; a chaser that isn't
## moving), walks (Chase), swings (Attack) and falls (Dying). A hit flashes it for FLASH_TICKS from the tick the sim
## says it was struck, so a pause holds the flash and a replay seek shows it where it was.
##
## Minions are pooled (the UnifiedView's `pool`) and appear only once their spawn is verified; everything the view shows
## comes from its data, so a reused view shows its new minion from the first frame.

## How long a hit's flash lasts, in ticks of shown game time.
const FLASH_TICKS: float = 8.0
## Where in the rise clip a minion starts: its last RISE_S (1.5 s) of 2.3, from the hand breaking the floor.
const RISE_FROM: float = 0.8
## When the attack clip's blow lands (seconds in: where the hand moves fastest); the clip is offset so it lands at the
## sim's swing (Unified.constants.minion_windup).
const BLOW_AT: float = 0.6
## Spreads the minions' gait phases: a key's last digits times this, in seconds, wrapped by the clip.
const PHASE_PER_KEY: float = 0.618034
## How many of a key's values the phase spreads over (a handle's key holds its generation in its high bits).
const PHASE_KEYS: int = 997

## Drawn over the skeleton's meshes while a hit flashes.
@export var hit_flash: Material

## Set by the host before _ready, anew each time the minion's view data changes, and null while the view is pooled.
var data: ViewMinion

var _meshes: Array[MeshInstance3D] = []
var _flashing: bool = false

@onready var _rig: CharacterRig = $Rig
@onready var _view: UnifiedView = $UnifiedView


func _ready() -> void:
	for found: Node in _rig.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(found as MeshInstance3D)


func _process(_delta: float) -> void:
	if data == null:
		return
	var now: float = Unified.session.shown_time
	var age: float = (now - data.since) / Unified.tick_hz
	var looping: float = now / Unified.tick_hz + float(_view.key % PHASE_KEYS) * PHASE_PER_KEY
	match data.phase:
		EnumMinionPhase.RISE:
			_rig.pose(Clips.SKELETON_RISE, RISE_FROM + age)
		EnumMinionPhase.CHASE:
			_rig.pose(Clips.SKELETON_WALK if data.moving else Clips.SKELETON_IDLE, looping)
		EnumMinionPhase.ATTACK:
			_rig.pose(Clips.SKELETON_ATTACK, BLOW_AT - Unified.constants.minion_windup + age)
		EnumMinionPhase.DYING:
			_rig.pose(Clips.SKELETON_DEATH, age)
		_:
			_rig.pose(Clips.SKELETON_IDLE, looping)
	_set_flash(data.struck != 0 and now - data.struck < FLASH_TICKS)


func _set_flash(on: bool) -> void:
	if on == _flashing:
		return
	_flashing = on
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = hit_flash if on else null
