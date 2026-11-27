class_name BrazierView
extends Node3D
## A brazier's view (View_Brazier, simulation/extension/frame.odin): the fire in the bowl of the brazier part (the
## level's stand, at whose foot the host poses this root). Lit, the fire burns (a shadowed light: the braziers are the
## lights a room is built round, docs/ART.md, Lighting), flaring up over FLARE_S from when it lit; unlit, an ember grows
## in the bowl as it is kindled. Both are functions of the view data and the shown time, so a rollback or a replay seek
## shows the fire as the state has it. Its whoosh is the play scene's, on the sim's Event_Brazier; the "[E] Light"
## prompt is the HUD's (Hud_Hero.kindle).

## How long a fire takes to flare up from nothing once lit (seconds).
const FLARE_S: float = 0.35
## The ember's size and light against the fire's, at a kindling's end (it grows from nothing).
const EMBER_SCALE: float = 0.35
const EMBER_LIGHT: float = 0.25

## Set by the host before _ready, and anew each time the brazier's view data changes.
var data: ViewBrazier

var _fire_scale: Vector3
var _fire_energy: float = 0.0

@onready var _fire: Fire = $Fire
@onready var _light: Flicker = $Fire/Light


func _ready() -> void:
	_fire_scale = _fire.scale
	_fire_energy = _light.base_energy


func _process(_delta: float) -> void:
	var size: float = 0.0
	if data.lit:
		var age: float = maxf(Unified.session.shown_time - data.lit_at, 0.0) / Unified.tick_hz
		size = clampf(age / FLARE_S, 0.0, 1.0)
		_light.base_energy = _fire_energy * size
	else:
		var kindled: float = data.kindled / 255.0
		size = EMBER_SCALE * kindled
		_light.base_energy = _fire_energy * EMBER_LIGHT * kindled
	_fire.visible = size > 0.0
	_fire.scale = _fire_scale * maxf(size, 0.01)
