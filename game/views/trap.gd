class_name TrapView
extends Node3D
## A trap's view (View_Trap, simulation/extension/frame.odin), the kind's model shown: spikes or the roller's pillar.
## The host poses the root at the trap's body: the spikes' sensor, a hand above the tile; the pillar as it goes. The
## spikes' height is the script's, a function of the view data and the session's shown time: up, they thrust out over
## RISE_S from `since`; down, they sink back over FALL_S. So a rollback or a replay seek shows them where they are.

## How long the spikes take to thrust up, and to sink back (seconds).
const RISE_S: float = 0.08
const FALL_S: float = 0.35
## The spike mesh's offset from where the model puts it (metres): down, its tips just under the tile's holes; up, a
## knee-high hedge of blades.
const DOWN_Y: float = -1.95
const UP_Y: float = -1.2

## Set by the host before _ready, and anew each time the trap's view data changes.
var data: ViewTrap:
	set(value):
		data = value
		if is_node_ready():
			_show()

@onready var _spikes_model: Node3D = $Spikes
@onready var _spikes: Node3D = $Spikes/floor_tile_big_spikes/spikes
@onready var _roller: Node3D = $Roller


func _ready() -> void:
	_show()


func _process(_delta: float) -> void:
	if data.kind != EnumTrapKind.SPIKES:
		return
	var age: float = maxf(Unified.session.shown_time - data.since, 0.0) / Unified.tick_hz
	var along: float = clampf(age / RISE_S, 0.0, 1.0) if data.up else 1.0 - clampf(age / FALL_S, 0.0, 1.0)
	_spikes.position.y = lerpf(DOWN_Y, UP_Y, along)


## The kind's model.
func _show() -> void:
	_spikes_model.visible = data.kind == EnumTrapKind.SPIKES
	_roller.visible = data.kind == EnumTrapKind.ROLLER
