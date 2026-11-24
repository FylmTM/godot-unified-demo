class_name MinionView
extends Node3D
## A skeleton minion's view (View_Minion, simulation/extension/frame.odin): the host poses this root at the minion's
## feet, turned to its facing, and the script animates the skeleton from the minion's phase and when it began, on the
## session's shown time: it climbs out of the floor (Rise), stands (Idle, asleep in a pack), walks (Chase), swings
## (Attack) and falls (Dying). A hit flashes it as soon as it is predicted (EMITTED): a flash a rollback takes back has
## already played, which a flash can afford.
##
## Minions are pooled (the UnifiedView's `pool`) and appear only once their spawn is verified: a reused view clears
## its flash in _sim_reused, and the data is null while it waits in the pool.

## How long a hit's flash lasts, in milliseconds.
const FLASH_MS: int = 120
## Where in the rise clip a minion starts: its last RISE_S (1.5 s) of 2.3, from the hand breaking the floor.
const RISE_FROM: float = 0.8
## Spreads the minions' gait phases: a key's last digits times this, in seconds, wrapped by the clip.
const PHASE_PER_KEY: float = 0.618034
## How many of a key's values the phase spreads over (a handle's key holds its generation in its high bits).
const PHASE_KEYS: int = 997

## Drawn over the skeleton's meshes while a hit flashes.
@export var hit_flash: Material

## Set by the host before _ready, anew each time the minion's view data changes, and null while the view is pooled.
var data: ViewMinion

var _meshes: Array[MeshInstance3D] = []
var _flash_until: int = 0
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
	var walking: float = now / Unified.tick_hz + float(_view.key % PHASE_KEYS) * PHASE_PER_KEY
	match data.phase:
		EnumMinionPhase.RISE:
			_rig.pose(Clips.SKELETON_RISE, RISE_FROM + age)
		EnumMinionPhase.IDLE:
			_rig.pose(Clips.SKELETON_IDLE, walking)
		EnumMinionPhase.CHASE:
			_rig.pose(Clips.SKELETON_WALK, walking)
		EnumMinionPhase.ATTACK:
			_rig.pose(Clips.SKELETON_ATTACK, age)
		EnumMinionPhase.DYING:
			_rig.pose(Clips.SKELETON_DEATH, age)
	_set_flash(Time.get_ticks_msec() < _flash_until)


func _sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if event is EventMinionHit and state == UnifiedSession.EVENT_EMITTED:
		_flash_until = Time.get_ticks_msec() + FLASH_MS


## The host reuses this view for another minion: the old one's flash is gone.
func _sim_reused() -> void:
	_flash_until = 0
	_set_flash(false)


func _set_flash(on: bool) -> void:
	if on == _flashing:
		return
	_flashing = on
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = hit_flash if on else null
