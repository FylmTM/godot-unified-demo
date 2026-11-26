class_name Effects
extends Node3D
## The play scene's one-shot effects: sparks where a skeleton is hit, a burst where a bolt bursts, dust where a prop
## lands hard, the crossbow's tracer, and a glint where a coin is picked up. The play scene calls them for the sim's
## events as soon as they are predicted (EMITTED): an effect a rollback takes back has already played, which an effect
## can afford, and one shown late would look worse.
##
## Each kind is a small pool of its scene, made once and reused in turn (the oldest goes first), so a fight's hundreds
## of hits make no node.

## How many of each effect play at once, the next one reusing the oldest: a cleave or a burst into a full crowd
## sparks on every skeleton it hits.
const POOL_SIZE: int = 48
## How long a tracer takes to fade, in seconds.
const TRACER_FADE_S: float = 0.15

## The effects' scenes (game/fx/).
@export var sparks_scene: PackedScene
@export var burst_scene: PackedScene
@export var dust_scene: PackedScene
@export var tracer_scene: PackedScene
@export var glint_scene: PackedScene

var _sparks: Pool
var _bursts: Pool
var _dust: Pool
var _tracers: Pool
var _glints: Pool
var _fades: Array[Tween] = []


func _ready() -> void:
	_sparks = _pool(sparks_scene)
	_bursts = _pool(burst_scene)
	_dust = _pool(dust_scene)
	_tracers = _pool(tracer_scene)
	_glints = _pool(glint_scene)
	_fades.resize(POOL_SIZE)


## Sparks at `at` (a skeleton hit).
func sparks(at: Vector3) -> void:
	_play(_sparks, at)


## A bolt's burst at `at`.
func burst(at: Vector3) -> void:
	_play(_bursts, at)


## A puff of dust at `at` (a prop landing hard).
func dust(at: Vector3) -> void:
	_play(_dust, at)


## A glint at `at` (a coin picked up: shown as predicted, while only a confirmed pickup counts in the purse).
func glint(at: Vector3) -> void:
	_play(_glints, at)


## A crossbow's tracer from `from` to `to`, fading over TRACER_FADE_S.
func tracer(from: Vector3, to: Vector3) -> void:
	var length: float = from.distance_to(to)
	if length < 0.01:
		return
	var index: int = _tracers.next
	var streak: MeshInstance3D = _tracers.take() as MeshInstance3D
	streak.visible = true
	streak.transparency = 0.0
	streak.look_at_from_position((from + to) / 2.0, to, Vector3.UP)
	streak.scale = Vector3(1, 1, length)
	if _fades[index] != null:
		_fades[index].kill()
	var fade: Tween = streak.create_tween()
	fade.tween_property(streak, ^"transparency", 1.0, TRACER_FADE_S)
	fade.tween_callback(streak.hide)
	_fades[index] = fade


func _pool(scene: PackedScene) -> Pool:
	var pool := Pool.new()
	for _i: int in POOL_SIZE:
		var node: Node3D = scene.instantiate() as Node3D
		add_child(node)
		pool.nodes.append(node)
	return pool


func _play(pool: Pool, at: Vector3) -> void:
	var particles: GPUParticles3D = pool.take() as GPUParticles3D
	particles.global_position = at
	particles.restart()


## A pool of one effect's nodes, taken in turn.
class Pool:
	extends RefCounted
	var nodes: Array[Node3D] = []
	## The index of the node take() gives next.
	var next: int = 0

	## The next node, the oldest in use.
	func take() -> Node3D:
		var node: Node3D = nodes[next]
		next = (next + 1) % nodes.size()
		return node
