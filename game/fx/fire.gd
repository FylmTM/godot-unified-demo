class_name Fire
extends Node3D
## A fire: additive flame particles over a warm, flickering light (Flicker). Torches, braziers, candles and lanterns
## are all this scene, scaled: the node's scale sizes the flames, `strength` the light.
##
## Shadows are on by default because a fire that grounds what stands near it is what makes a dark room read; the small
## fires (torches on walls, candles, lanterns) turn them off. Each shadowed light costs a cube shadow map redrawn every frame (its flicker
## moves it), so a room keeps them to a few (docs/ART.md, Lighting).

## Whether the light casts shadows.
@export var casts_shadows: bool = true
## Scales the light's energy and reach, apart from the flames' size.
@export_range(0.1, 4.0) var strength: float = 1.0

@onready var _light: Flicker = $Light


func _ready() -> void:
	_light.shadow_enabled = casts_shadows
	_light.light_energy *= strength
	_light.base_energy = _light.light_energy
	_light.omni_range *= sqrt(strength)
