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
## speed near a threshold doesn't flicker between two. An action (a pick-up, a throw, an attack) is a one-shot clip
## posed at its age, (shown_time - action_started) / tick_hz seconds, from the moment of the clip its action starts
## at, so the clip's release or blow lands on the sim's: an attack's clip is offset so its blow (sampled from the clip)
## comes at the class's windup (Unified.constants.class_windups). A hero carrying walks with plain gaits: no clip
## holds a load. A hero down falls where its body stands (the death clip, held on its last frame), and one that just
## rose blinks while its grace lasts.

## A standing hero walks from this speed, and a walking one stands below the lower (metres per second).
const WALK_FROM: float = 0.5
const STAND_BELOW: float = 0.3
## A hero walking ahead runs from this speed, and a running one walks below the lower (metres per second).
const RUN_FROM: float = 3.4
const WALK_BELOW: float = 3.0
## How fast a hero in its grace blinks: shown, then hidden, this many ticks each (of the shown game time, so a pause
## holds it and a replay seek lands on the right half).
const GRACE_BLINK_TICKS: float = 5.0
## Spreads the heroes' gait phases: a player's key times this, in seconds, wrapped by the clip.
const PHASE_PER_KEY: float = 0.618034
## Where in its clip each action starts (seconds): the pick-up past the clip's first lean, the throw past its draw-back,
## so its arm comes through at the sim's THROW_WINDUP_S (0.25 s), when the prop leaves the hands.
const PICK_UP_FROM: float = 0.25
const THROW_FROM: float = 0.4
## When each class's attack clip lands its blow or loosens its shot (seconds in: where the hand moves fastest; the
## Rogue's raises the crossbow first, so its shot is the recoil after).
const KNIGHT_BLOW_AT: float = 0.275
const BARBARIAN_BLOW_AT: float = 0.4
const MAGE_CAST_AT: float = 0.1
const ROGUE_SHOT_AT: float = 0.375 # the recoil: past the raise, the crossbow up
## KayKit's two-handed shoot clip stands side-on, the crossbow out of the model's right side: the rig turns this much
## (radians about +Y) while the Rogue shoots, so the crossbow points along the hero's facing.
const ROGUE_SHOT_TURN: float = PI / 2

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
	var now: float = Unified.session.shown_time
	match data.action:
		EnumAction.PICK_UP:
			_rig.pose(Clips.PICK_UP, PICK_UP_FROM + (now - data.action_started) / Unified.tick_hz)
		EnumAction.THROW:
			_rig.pose(Clips.THROW, THROW_FROM + (now - data.action_started) / Unified.tick_hz)
		EnumAction.DOWN:
			_rig.pose(Clips.DEATH, (now - data.action_started) / Unified.tick_hz)
		EnumAction.ATTACK:
			_pose_attack((now - data.action_started) / Unified.tick_hz)
		_:
			_rig.pose(_gait(), now / Unified.tick_hz + float(_view.player) * PHASE_PER_KEY)
	var shooting: bool = data.action == EnumAction.ATTACK and data.class == EnumClass.ROGUE
	_rig.rotation.y = ROGUE_SHOT_TURN if shooting else 0.0
	_rig.visible = not data.grace or fposmod(now, 2.0 * GRACE_BLINK_TICKS) < GRACE_BLINK_TICKS


## Poses the class's attack `age` seconds in, its blow lined up with the class's windup.
func _pose_attack(age: float) -> void:
	var windup: float = Unified.constants.class_windups[data.class]
	match data.class:
		EnumClass.BARBARIAN:
			_rig.pose(Clips.BARBARIAN_CLEAVE, BARBARIAN_BLOW_AT - windup + age)
		EnumClass.MAGE:
			_rig.pose(Clips.MAGE_BOLT, MAGE_CAST_AT - windup + age)
		EnumClass.ROGUE:
			_rig.pose(Clips.ROGUE_SHOOT, ROGUE_SHOT_AT - windup + age)
		_:
			_rig.pose(Clips.KNIGHT_SLASH, KNIGHT_BLOW_AT - windup + age)


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
