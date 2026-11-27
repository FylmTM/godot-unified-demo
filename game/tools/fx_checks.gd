class_name FxChecks
extends RefCounted
## The effects' and the light's promises, checked: the godot suite's validate step runs them (game/tools/validate.gd)
## beside the art and app checks, so a broken budget, an effect a cancel can't undo or a cutaway that never comes back
## fails the suite instead of a fight.
##
## - Budgets: a crowd's hundred deaths in one frame start at most Effects.STARTS_PER_FRAME puffs; hits a body's width
##   apart in one frame merge into one.
## - The event-state rule: a fireball's scorch and the slam's crack, CANCELLED, are gone within 0.1 s, and CONFIRMED,
##   stay; each lingering effect is undone by its own event's id alone; the revive's stars wait for CONFIRMED.
## - Lighting: the play scene lights the vault with its own Environment, whose ambient follows the lit braziers' count
##   up and down, and never changes the Environment the file holds; a level without braziers to follow keeps its own.
## - The cutaway: a wall between the camera and a hero is cut, and comes back whole (its own material) once the hero
##   has gone; a wall behind the hero is never cut.
##
## Each check makes what it checks under the run's tree and steps it by hand (Effects.advance, Lighting.follow,
## Cutaway.update), in one frame. Events made here (`EventFireballBurst.new()`) carry the default fields and id 0, so
## the keyed checks call the effects by id directly. Each problem is reported through the validate run's log capture.

const EFFECTS: String = "res://game/play/effects.tscn"
const EFFECTS_SCRIPT: String = "res://game/play/effects.gd"
const PLAY: String = "res://game/play/play.tscn"
const LIGHTING_SCRIPT: String = "res://game/play/lighting.gd"
const CRYPT: String = "res://game/environments/crypt.tres"
const VAULT: String = "res://game/environments/vault.tres"
const CUTAWAY_SCRIPT: String = "res://game/play/cutaway.gd"
const CUTAWAY_MATERIAL: String = "res://game/fx/cutaway.tres"
const WALL: String = "res://game/levels/parts/crypt/wall.tscn"
## How near two ambient energies must be once eased for long enough.
const AMBIENT_NEAR: float = 0.005

## How many problems the checks found.
var problems: int = 0

var _log: UnifiedLogCapture
var _tree_root: Node


## Checks report to `log_capture`; `tree_root` is where what is checked runs.
func _init(log_capture: UnifiedLogCapture, tree_root: Node) -> void:
	_log = log_capture
	_tree_root = tree_root


## Runs every check.
func run() -> void:
	_check_budgets()
	_check_lingering()
	_check_news()
	_check_lighting()
	_check_cutaway()


func _check_budgets() -> void:
	var effects: Effects = _effects()
	var started: int = 0
	for death: int in 100:
		if effects.play(Effects.Kind.BONE_PUFF, Vector3(death * 2.0, 0, 0)):
			started += 1
	_expect(started == Effects.STARTS_PER_FRAME, "a hundred deaths in a frame start %d puffs, not %d" % [
		Effects.STARTS_PER_FRAME, started], EFFECTS_SCRIPT)
	_expect(effects.playing(Effects.Kind.BONE_PUFF) == started, "every puff started plays", EFFECTS_SCRIPT)
	started = 0
	for hit: int in 10:
		if effects.play(Effects.Kind.SPARKS, Vector3(hit * 0.05, 0, 0)):
			started += 1
	_expect(started == 1, "ten hits within a body's width merge into 1 sparks, not %d" % started, EFFECTS_SCRIPT)
	_free(effects)


func _check_lingering() -> void:
	var effects: Effects = _effects()
	for event: UnifiedEvent in [EventFireballBurst.new(), EventBossSlam.new()]:
		var kind: String = "a fireball's scorch" if event is EventFireballBurst else "the slam's crack"
		effects.on_event(event, UnifiedSession.EVENT_EMITTED)
		effects.advance(0.05)
		_expect(effects.shown(event.id) > 0.9, "%s shows once EMITTED" % kind, EFFECTS_SCRIPT)
		effects.on_event(event, UnifiedSession.EVENT_CANCELLED)
		effects.advance(0.1)
		_expect(effects.shown(event.id) == 0.0, "%s is gone 0.1 s after its CANCELLED" % kind, EFFECTS_SCRIPT)
		effects.on_event(event, UnifiedSession.EVENT_EMITTED)
		effects.on_event(event, UnifiedSession.EVENT_CONFIRMED)
		effects.advance(2.0)
		_expect(effects.shown(event.id) > 0.9, "%s stays after its CONFIRMED" % kind, EFFECTS_SCRIPT)
		effects.clear()
	effects.scorch(Vector3(-4, 0, 0), 101)
	effects.crack(Vector3(4, 0, 0), 102)
	effects.cancel(101)
	effects.forget(102)
	effects.cancel(102)  # too late: confirmed is final
	effects.advance(0.1)
	_expect(effects.shown(101) == 0.0, "the decal of the event cancelled is gone", EFFECTS_SCRIPT)
	_expect(effects.shown(102) > 0.9, "the decal of the event confirmed stays, whatever else is cancelled",
		EFFECTS_SCRIPT)
	_free(effects)


func _check_news() -> void:
	var effects: Effects = _effects()
	var revived := EventHeroRevived.new()
	effects.on_event(revived, UnifiedSession.EVENT_EMITTED)
	_expect(effects.playing(Effects.Kind.STARS) == 0, "a revive's stars wait for its CONFIRMED", EFFECTS_SCRIPT)
	effects.on_event(revived, UnifiedSession.EVENT_CONFIRMED)
	_expect(effects.playing(Effects.Kind.STARS) == 1, "a revive's stars rise on its CONFIRMED", EFFECTS_SCRIPT)
	_free(effects)


func _check_lighting() -> void:
	var vault: Environment = load(VAULT)
	var ends: Vector2 = vault.get_meta(Lighting.BRAZIER_AMBIENT, Vector2.ZERO)
	_expect(ends.x > 0.0 and ends.y > ends.x, "the vault's ambient brightens with its braziers", VAULT)
	var mapped: Environment = _play_lighting().get(&"vault")
	_expect(mapped == vault, "the play scene lights the vault with vault.tres", PLAY)
	var lighting := Lighting.new()
	lighting.environment = load(CRYPT)
	lighting.environments = {&"vault": vault}
	_tree_root.add_child(lighting)
	lighting.set_process(false)
	lighting.show_level(&"vault")
	_expect(lighting.environment != vault, "the vault's ambient changes on a copy, never on vault.tres", LIGHTING_SCRIPT)
	var dark: float = lighting.environment.ambient_light_energy
	_expect(is_equal_approx(dark, ends.x), "the vault starts dark (%.3f, not %.3f)" % [ends.x, dark], LIGHTING_SCRIPT)
	for step: Array in [[4, ends.y], [2, lerpf(ends.x, ends.y, 0.5)], [0, ends.x], [3, lerpf(ends.x, ends.y, 0.75)]]:
		var lit: int = step[0]
		var goal: float = step[1]
		lighting.follow(lit, 4, 4.0)
		var shown: float = lighting.environment.ambient_light_energy
		_expect(absf(shown - goal) < AMBIENT_NEAR, "%d of 4 braziers lit: the ambient %.3f, not %.3f" % [lit, goal, shown],
			LIGHTING_SCRIPT)
	_expect(is_equal_approx(vault.ambient_light_energy, ends.x), "vault.tres's own ambient stays as the file has it",
		VAULT)
	lighting.show_level(&"floor_1")
	var crypt_ambient: float = lighting.environment.ambient_light_energy
	lighting.follow(4, 4, 4.0)
	_expect(lighting.environment.resource_path == CRYPT and lighting.environment.ambient_light_energy == crypt_ambient,
		"a level without a brazier ambient keeps the crypt's, unchanged", LIGHTING_SCRIPT)
	_tree_root.remove_child(lighting)
	lighting.free()


func _check_cutaway() -> void:
	var level := Node3D.new()
	var shown := Node3D.new()  # the floor shown under the level root
	level.add_child(shown)
	var wall: Node3D = (load(WALL) as PackedScene).instantiate()
	shown.add_child(wall)  # along x, at z = 0, 1 m thick
	var cutaway := Cutaway.new()
	cutaway.material = load(CUTAWAY_MATERIAL)
	_tree_root.add_child(level)
	_tree_root.add_child(cutaway)
	cutaway.set_process(false)
	cutaway.track(level)
	var eye := Vector3(0, 15.7, 9.3)  # the game camera's angle, from 18 m
	var meshes: Array[Node] = wall.find_children("*", "MeshInstance3D", true, false)
	cutaway.update(eye, [Vector3(0, 0, 3)], 1.0)
	_expect(cutaway.cut_of(wall) == 0.0, "a wall behind a hero stays whole", CUTAWAY_SCRIPT)
	cutaway.update(eye, [Vector3(0, 0, 3), Vector3(0.5, 0, -1.5)], 1.0)
	_expect(is_equal_approx(cutaway.cut_of(wall), Cutaway.CUT_MAX), "a wall between the camera and a hero is cut",
		CUTAWAY_SCRIPT)
	for mesh: Node in meshes:
		_expect((mesh as MeshInstance3D).material_override == cutaway.material, "a cut wall draws with the cutaway's",
			CUTAWAY_SCRIPT)
	cutaway.update(eye, [Vector3(0, 0, -9)], 0.1)
	_expect(cutaway.cut_of(wall) > 0.0 and cutaway.cut_of(wall) < Cutaway.CUT_MAX,
		"a wall the hero left comes back gradually", CUTAWAY_SCRIPT)
	cutaway.update(eye, [Vector3(0, 0, -9)], 1.0)
	_expect(cutaway.cut_of(wall) == 0.0, "a wall the hero left is whole again", CUTAWAY_SCRIPT)
	for mesh: Node in meshes:
		_expect((mesh as MeshInstance3D).material_override == null, "a whole wall draws with its own material again",
			CUTAWAY_SCRIPT)
	_tree_root.remove_child(level)
	level.free()
	_tree_root.remove_child(cutaway)
	cutaway.free()


## The play scene's Lighting.environments, as the scene file sets it.
func _play_lighting() -> Dictionary:
	var state: SceneState = (load(PLAY) as PackedScene).get_state()
	for node: int in state.get_node_count():
		if state.get_node_name(node) != &"Lighting":
			continue
		for property: int in state.get_node_property_count(node):
			if state.get_node_property_name(node, property) == &"environments":
				return state.get_node_property_value(node, property)
	return {}


func _effects() -> Effects:
	var effects: Effects = (load(EFFECTS) as PackedScene).instantiate()
	_tree_root.add_child(effects)
	effects.set_process(false)
	return effects


func _free(effects: Effects) -> void:
	_tree_root.remove_child(effects)
	effects.free()


func _expect(cond: bool, what: String, at: String) -> void:
	if not cond:
		_problem("expected " + what, at)


func _problem(message: String, at: String) -> void:
	problems += 1
	_log.add(message, at)
