class_name HeroView
extends Node3D
## A hero's view (View_Hero, simulation/extension/frame.odin): the host poses this root at the hero's feet, turned to
## its facing, and the script shows the class's character and animates it.
##
## The character is the class's CharacterRig scene (game/characters/heroes/), made anew when the class changes. Its
## pose is a function of the view data and the session's shown time, never of a clock of its own: the gait (idle,
## walk, run, backwards, strafes) comes from the velocity in the hero's own frame and loops on the shown time, so after
## a rollback or a replay seek the hero shows the frame the state says. Each hero's gait runs at its own phase (from
## its player's key), so a party walking together doesn't step in lockstep, and a gait changes past a margin, so a
## speed near a threshold doesn't flicker between two. The attacks' one-shots will pose at their age,
## (shown_time - action_started) / tick_hz seconds, once the sim has actions (docs/plan.md, Milestone 2: the design).

## A standing hero walks from this speed, and a walking one stands below the lower (metres per second).
const WALK_FROM: float = 0.5
const STAND_BELOW: float = 0.3
## A hero walking ahead runs from this speed, and a running one walks below the lower (metres per second).
const RUN_FROM: float = 3.4
const WALK_BELOW: float = 3.0
## Spreads the heroes' gait phases: a player's key times this, in seconds, wrapped by the clip.
const PHASE_PER_KEY: float = 0.618034

## Each class's character.
@export var knight: PackedScene
@export var barbarian: PackedScene
@export var mage: PackedScene
@export var rogue: PackedScene

## Set by the host before _ready, and anew each time the hero's view data changes.
var data: ViewHero:
	set(value):
		var class_changed: bool = data == null or data.class != value.class
		data = value
		if class_changed and is_node_ready():
			_show_class()

var _rig: CharacterRig
var _moving: bool = false
var _running: bool = false

@onready var _view: UnifiedView = $UnifiedView


func _ready() -> void:
	_show_class()


func _process(_delta: float) -> void:
	var phase: float = float(_view.player) * PHASE_PER_KEY
	_rig.pose(_gait(), Unified.session.shown_time / Unified.tick_hz + phase)


## Replaces the character with the class's.
func _show_class() -> void:
	if _rig != null:
		_rig.free()
	_rig = _class_scene().instantiate() as CharacterRig
	add_child(_rig)


## The class's character scene (the Knight's for a class no hero plays: `Any`).
func _class_scene() -> PackedScene:
	match data.class:
		EnumClass.BARBARIAN:
			return barbarian
		EnumClass.MAGE:
			return mage
		EnumClass.ROGUE:
			return rogue
	return knight


## The gait from the velocity in the hero's frame (x to its right, y ahead): standing, walking or running ahead,
## walking backwards, or strafing; the Barbarian stands with its axe ready and the Rogue runs with its crossbow up.
func _gait() -> StringName:
	var velocity: Vector2 = data.velocity
	_moving = velocity.length() >= (STAND_BELOW if _moving else WALK_FROM)
	_running = _moving and velocity.y >= (WALK_BELOW if _running else RUN_FROM)
	if not _moving:
		return Clips.BARBARIAN_IDLE if data.class == EnumClass.BARBARIAN else Clips.IDLE
	if _running:
		return Clips.ROGUE_RUN if data.class == EnumClass.ROGUE else Clips.RUN
	if velocity.y >= absf(velocity.x):
		return Clips.WALK
	if -velocity.y >= absf(velocity.x):
		return Clips.WALK_BACKWARDS
	return Clips.STRAFE_RIGHT if velocity.x > 0.0 else Clips.STRAFE_LEFT
