class_name Flicker
extends OmniLight3D
## Makes a fire's light breathe: its energy and position drift with smooth noise around where the scene put them.
##
## Purely a view effect, so its randomness never touches the simulation. Each light hashes its own world position into
## the noise's seed, so two torches side by side never pulse in step, and the same torch flickers the same way every
## run. A shadowed fire's shadows sway with the light.

## How far the energy swings around the scene's value, as a fraction of it.
@export_range(0.0, 0.5) var energy_swing: float = 0.12
## How far the light wanders from its place, in metres.
@export_range(0.0, 0.2) var position_swing: float = 0.03
## How fast the flicker runs, in noise units per second.
@export var speed: float = 6.0

## The energy it swings around: the light's own at ready (a Fire that scales the light sets it again).
var base_energy: float = 0.0

var _noise: FastNoiseLite = FastNoiseLite.new()
var _base_position: Vector3 = Vector3.ZERO
var _time: float = 0.0


func _ready() -> void:
	base_energy = light_energy
	_base_position = position
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.5
	_noise.seed = hash(global_position.snapped(Vector3.ONE * 0.01))


func _process(delta: float) -> void:
	_time += delta * speed
	light_energy = base_energy * (1.0 + energy_swing * _noise.get_noise_1d(_time))
	position = _base_position + position_swing * Vector3(
		_noise.get_noise_2d(_time, 17.0), _noise.get_noise_2d(_time, 31.0), _noise.get_noise_2d(_time, 53.0)
	)
