class_name EliteView
extends Node3D
## An elite's view (View_Elite, simulation/extension/frame.odin): the host poses this root at the elite's feet, turned
## to its facing, and the script shows its kind's skeleton (game/characters/skeletons/), animates it, and draws its
## health bar and, on a Warrior whose shield is up, the shield's glint.
##
## Its pose is a function of the view data and the session's shown time, as a hero's is: its phase at its age (the rise
## from the clip's hand breaking the floor, an attack timed so its blow lands at the kind's windup
## (Unified.constants.elite_windups), a summoning's cast, hanging limp while a Barbarian heaves and throws it, the fall
## and the sink), a stagger's hit at the last hit's age, else a gait from its velocity (a Warrior standing with its
## shield up holds it raised). A hit flashes it; the glint pulses on the shown time. So after a rollback or a replay
## seek the elite shows the frame the state says.
##
## Elites are pooled (the UnifiedView's `pool`): the data setter takes null between two elites, then the next one's,
## and a kind change makes that kind's skeleton anew. Each appears once its spawn is verified (the extension's policy).
##
## The boss, the Bone King, is an elite of its own kind: a skeleton Warrior Unified.constants.boss_scale times as big,
## its health bar the HUD's (no billboard). It cleaves in the Knight's slash, roars as its stage begins, and slams: its
## ring on the floor fills over the slam's windup (from the phase's start, so a seek shows it as far as the state says)
## and the axe lands as it closes. While warded it stands in a pale shell (Ward) that pulses on the shown time.

## A standing elite walks from this speed, and a walking one stands below the lower (metres per second).
const WALK_FROM: float = 0.4
const STAND_BELOW: float = 0.25
## Where in the rise clip an elite starts: the minions' (MinionCrowdView.RISE_FROM), from the hand breaking the floor.
const RISE_FROM: float = 0.8
## When each kind's attack clip lands its blow (seconds in: where the weapon moves fastest), lined up with the sim's.
const WARRIOR_BLOW_AT: float = 0.6
const ROGUE_STAB_AT: float = 0.5
const MAGE_CAST_AT: float = 0.1
const KING_CLEAVE_AT: float = 0.45
const KING_SLAM_AT: float = 0.75
## The dead sink out of sight over the last SINK_S of their row's DEATH_S, this deep (metres).
const SINK_S: float = 0.6
const SINK_DEPTH: float = 1.0
## Spreads the elites' gait phases: a key times this, in seconds, wrapped by the clip.
const PHASE_PER_KEY: float = 0.618034
## The glint: its period (ticks of shown time) and how bright it gets.
const GLINT_TICKS: float = 96.0
const GLINT_PEAK: float = 0.45
## The King's ward: its pulse's period (ticks of shown time), and how bright it burns at its dimmest and brightest.
const WARD_TICKS: float = 128.0
const WARD_LOW: float = 0.6
const WARD_HIGH: float = 1.2

## Each kind's skeleton.
@export var warrior: PackedScene
@export var rogue: PackedScene
@export var mage: PackedScene
@export var king: PackedScene
## Drawn over the skeleton for a moment after a hit.
@export var flash: Material
## Drawn over a Warrior's shield while it guards.
@export var glint: Material

## Set by the host before _ready, anew each time the elite's view data changes, and null while the view is pooled.
var data: ViewElite:
	set(value):
		data = value
		if value != null and value.kind != _kind and is_node_ready():
			_show_kind()

var _rig: CharacterRig
var _kind: int = -1
var _meshes: Array[MeshInstance3D] = []
var _shield: MeshInstance3D = null
var _moving: bool = false
var _flashing: bool = false
var _dimmed: StandardMaterial3D = null

@onready var _view: UnifiedView = $UnifiedView
@onready var _bar: MeshInstance3D = $Bar
@onready var _ward: MeshInstance3D = $Ward
@onready var _slam_ring: MeshInstance3D = $SlamRing


func _ready() -> void:
	_slam_ring.scale = Vector3.ONE * Unified.constants.boss_slam_radius  # the quad is 2 m across
	if data != null:
		_show_kind()


func _process(_delta: float) -> void:
	if data == null or _rig == null:
		return
	var now: float = Unified.session.shown_time
	var age: float = maxf(now - data.since, 0.0) / Unified.tick_hz
	var sink: float = 0.0
	match data.phase:
		EnumElitePhase.RISE:
			_rig.pose(Clips.SKELETON_RISE, RISE_FROM + age)
		EnumElitePhase.ATTACK:
			_pose_attack(age)
		EnumElitePhase.SUMMON:
			_rig.pose(Clips.MAGE_CAST, age)
		EnumElitePhase.HELD, EnumElitePhase.THROWN:
			_rig.pose(Clips.SKELETON_LIMP, age)
		EnumElitePhase.DYING:
			_rig.pose(Clips.SKELETON_DEATH, age)
			var sinking: float = clampf((age - Unified.constants.minion_death + SINK_S) / SINK_S, 0.0, 1.0)
			sink = SINK_DEPTH * _rig.scale.y * sinking  # the King, bigger, sinks deeper
		EnumElitePhase.SLAM:
			_rig.pose(Clips.BOSS_SLAM, _attack_time(age, KING_SLAM_AT, Unified.constants.boss_slam_windup))
		_ when data.warded and age < Unified.constants.boss_roar:
			_rig.pose(Clips.SKELETON_TAUNT, age)
		_:
			if data.staggered:
				_rig.pose(Clips.HIT, maxf(now - data.struck, 0.0) / Unified.tick_hz)
			else:
				_rig.pose(_gait(), now / Unified.tick_hz + float(_view.key % 997) * PHASE_PER_KEY)
	_rig.position.y = -sink
	_show_boss(now, age)
	_bar.visible = data.phase != EnumElitePhase.DYING and data.kind != EnumEliteKind.KING
	_bar.set_instance_shader_parameter(&"fraction", clampf(float(data.hp) / float(data.hp_max), 0.0, 1.0))
	_set_flash(data.struck != 0 and now - data.struck < MinionCrowd.FLASH_TICKS)
	if _shield != null and not _flashing:
		_shield.material_overlay = glint if data.guard else null
		var pulse: float = 0.5 - 0.5 * cos(TAU * fposmod(now, GLINT_TICKS) / GLINT_TICKS)
		_shield.set_instance_shader_parameter(&"glint", GLINT_PEAK * pulse * pulse)


## Poses the kind's attack `age` seconds in, its blow lined up with the kind's windup.
func _pose_attack(age: float) -> void:
	match data.kind:
		EnumEliteKind.ROGUE:
			_rig.pose(Clips.ELITE_ROGUE_STAB, _attack_time(age, ROGUE_STAB_AT))
		EnumEliteKind.MAGE:
			_rig.pose(Clips.MAGE_BOLT, _attack_time(age, MAGE_CAST_AT))
		EnumEliteKind.KING:
			_rig.pose(Clips.KNIGHT_SLASH, _attack_time(age, KING_CLEAVE_AT))
		_:
			_rig.pose(Clips.SKELETON_ATTACK, _attack_time(age, WARRIOR_BLOW_AT))


## The time in an attack clip whose blow is `blow_at` seconds in, `age` seconds into the attack, so the blow lands at
## its windup (the kind's attack's, unless given: the King's slam): a clip whose blow comes sooner starts past its
## beginning; one whose blow comes later plays its lead-in slowed over the windup (as HeroView's attacks do).
func _attack_time(age: float, blow_at: float, windup: float = -1.0) -> float:
	if windup < 0.0:
		windup = Unified.constants.elite_windups[data.kind]
	if blow_at >= windup:
		return blow_at - windup + age
	if age < windup:
		return age * blow_at / windup
	return blow_at + age - windup


## The King's ward while it is warded, pulsing on the shown time `now` (ticks), and its slam's ring over the slam's
## windup, `age` seconds into the phase, filling as the blow nears.
func _show_boss(now: float, age: float) -> void:
	_ward.visible = data.warded and data.phase != EnumElitePhase.DYING
	if _ward.visible:
		var pulse: float = 0.5 - 0.5 * cos(TAU * fposmod(now, WARD_TICKS) / WARD_TICKS)
		_ward.set_instance_shader_parameter(&"strength", lerpf(WARD_LOW, WARD_HIGH, pulse))
	var windup: float = Unified.constants.boss_slam_windup
	_slam_ring.visible = data.phase == EnumElitePhase.SLAM and age < windup
	if _slam_ring.visible:
		_slam_ring.set_instance_shader_parameter(&"fill", age / windup)


## The gait from the velocity in the elite's frame: walking, or standing (a Warrior with its shield up holds it
## raised).
func _gait() -> StringName:
	_moving = data.velocity.length() >= (STAND_BELOW if _moving else WALK_FROM)
	if _moving:
		return Clips.SKELETON_WALK
	return Clips.KNIGHT_BLOCK if data.guard else Clips.SKELETON_IDLE


## Replaces the skeleton with the kind's, and finds its meshes (the flash) and its shield (the glint).
func _show_kind() -> void:
	if _rig != null:
		_rig.free()
	_kind = data.kind
	match data.kind:
		EnumEliteKind.ROGUE:
			_rig = rogue.instantiate() as CharacterRig
		EnumEliteKind.MAGE:
			_rig = mage.instantiate() as CharacterRig
		EnumEliteKind.KING:
			_rig = king.instantiate() as CharacterRig
			_rig.scale = Vector3.ONE * Unified.constants.boss_scale
		_:
			_rig = warrior.instantiate() as CharacterRig
	add_child(_rig)
	_meshes.clear()
	for found: Node in _rig.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(found as MeshInstance3D)
	var left: Node = _rig.get_node_or_null(^"HandL/Weapon")
	_shield = null
	if (data.kind == EnumEliteKind.WARRIOR or data.kind == EnumEliteKind.KING) and left != null:
		_shield = left.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_flashing = false


## Shows or hides the hit's flash over every mesh (the shield's glint gives way to it).
func _set_flash(on: bool) -> void:
	if on == _flashing:
		return
	_flashing = on
	var overlay: Material = flash if Flashes.on else _dimmed_flash()
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = overlay if on else null


## The hit's flash with flashes off (Flashes.on, Settings.flashes): half as bright, the additive overlay with its
## colour scaled, made once.
func _dimmed_flash() -> Material:
	if _dimmed == null:
		_dimmed = flash.duplicate() as StandardMaterial3D
		_dimmed.albedo_color = (flash as StandardMaterial3D).albedo_color * Flashes.DIMMED
	return _dimmed
