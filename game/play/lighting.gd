class_name Lighting
extends WorldEnvironment
## The play scene's light: each level's Environment, and the ambient of a room lit by its braziers.
##
## `environments` maps a level's name (EnumLevel.name: "hub", "vault") to its Environment (game/environments/); a level
## it doesn't name keeps the node's own, the crypt's. An Environment whose metadata names a `brazier_ambient` (a
## Vector2: the ambient energy with no brazier lit, and with every one lit) follows the floor's braziers: its ambient
## eases toward its share of the brazier views that are lit, so the vault brightens as the party lights it and darkens
## as the King puts its fires out. The count comes from the views' data (ViewBrazier.lit), never from the sim's events:
## a rollback or a replay seek shows the room as the state has it. The look-dev scene lights its vault shots by the same
## rule (brazier_ambient_energy).

## How fast the ambient closes on its goal, per second (exponential).
const AMBIENT_RATE: float = 2.0
## The metadata an Environment names its brazier-lit ambient by.
const BRAZIER_AMBIENT: StringName = &"brazier_ambient"

## Each level's Environment, by the level's name (EnumLevel.name); a level not here keeps the node's own.
@export var environments: Dictionary[StringName, Environment] = {}

## The node's own Environment (the crypt's), for every level `environments` doesn't name.
var _default: Environment = null
## The shown level's brazier ambient (none with no brazier lit, all with every one): ZERO when it follows none.
var _brazier_ambient: Vector2 = Vector2.ZERO


func _ready() -> void:
	_default = environment


func _process(delta: float) -> void:
	if _brazier_ambient == Vector2.ZERO:
		return
	var lit: int = 0
	var braziers: Array[Node] = Unified.session.get_views(EnumView.BRAZIER)
	for brazier: Node in braziers:
		if (brazier as BrazierView).data.lit:
			lit += 1
	follow(lit, braziers.size(), delta)


## Shows the level `level_name`'s Environment: its own copy when its ambient follows the braziers, starting dark.
func show_level(level_name: StringName) -> void:
	var chosen: Environment = environments.get(level_name, _default)
	_brazier_ambient = chosen.get_meta(BRAZIER_AMBIENT, Vector2.ZERO)
	if _brazier_ambient == Vector2.ZERO:
		environment = chosen
		return
	environment = chosen.duplicate()
	environment.ambient_light_energy = _brazier_ambient.x


## Eases the ambient over `delta` seconds toward its share of `lit` braziers of `total` (the play scene's frames ask
## with the views' count; a check, by hand). Nothing while the level's Environment follows no braziers.
func follow(lit: int, total: int, delta: float) -> void:
	if _brazier_ambient == Vector2.ZERO:
		return
	var goal: float = brazier_ambient_energy(environment, lit, total)
	environment.ambient_light_energy = lerpf(environment.ambient_light_energy, goal, 1.0 - exp(-AMBIENT_RATE * delta))


## The ambient energy `environment` shows with `lit` of its floor's `total` braziers lit: from its brazier_ambient's
## dark end to its lit end (its own ambient energy when it names none).
static func brazier_ambient_energy(shown: Environment, lit: int, total: int) -> float:
	var ends: Vector2 = shown.get_meta(BRAZIER_AMBIENT, Vector2.ZERO)
	if ends == Vector2.ZERO:
		return shown.ambient_light_energy
	return lerpf(ends.x, ends.y, float(lit) / total if total > 0 else 0.0)
