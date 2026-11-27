class_name ShrineView
extends Node3D
## A hub shrine's view (View_Shrine, simulation/extension/frame.odin): the host poses this root at its marker. The
## shrine's candles show what it sets: the difficulty shrine's burn warm on Normal and red on Hard; the mode shrine's
## skull lights up for the Pit, dark for the crypt. Each turn flares the candles for FLARE_S, a function of the shown
## time since the turn (View_Shrine.turned), so a rollback or a replay seek shows the flare where it is.

## The candles' light on Normal (and on the mode shrine), on Hard, and the skull's for the Pit.
const WARM: Color = Color(1.0, 0.68, 0.36)
const RED: Color = Color(1.0, 0.22, 0.12)
const SKULL_LIT: Color = Color(0.55, 1.0, 0.6)
## How long a turn's flare lasts (seconds), and how much brighter the candles burn at its start.
const FLARE_S: float = 0.6
const FLARE_GAIN: float = 2.5

## Set by the host before _ready and anew each time the shrine's view data changes.
var data: ViewShrine:
	set(value):
		data = value
		if is_node_ready():
			_show()

## The candles' energy as the scene sets it (the flare scales the flicker's base from it).
var _candle_energy: float = 0.0

@onready var _candles: Flicker = $Candles
@onready var _skull: Node3D = $Skull
@onready var _skull_light: OmniLight3D = $Skull/Light


func _ready() -> void:
	_candle_energy = _candles.base_energy  # the child's _ready came first
	_show()


func _process(_delta: float) -> void:
	if data == null or data.turned == 0:
		return
	var since: float = (Unified.session.shown_time - data.turned) / Unified.tick_hz
	var flare: float = clampf(1.0 - since / FLARE_S, 0.0, 1.0) if since >= 0.0 else 0.0
	_candles.base_energy = _candle_energy * (1.0 + FLARE_GAIN * flare)


func _show() -> void:
	if data == null:
		return
	var hard: bool = data.sets == EnumShrineSetting.DIFFICULTY and data.value == EnumDifficulty.HARD
	_candles.light_color = RED if hard else WARM
	_skull.visible = data.sets == EnumShrineSetting.MODE
	_skull_light.visible = data.sets == EnumShrineSetting.MODE and data.value == EnumMode.PIT
	_skull_light.light_color = SKULL_LIT
