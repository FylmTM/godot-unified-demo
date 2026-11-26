class_name FireballTargetView
extends Node3D
## Where a local Mage's fireball would land (View_Fireball_Target, simulation/extension/frame.odin): a ring on the floor,
## posed by the host at the rules' own fireball_target on the player's newest input, so it is where the cast will
## land (a wall on the way brings it short, as it will the fireball). Faint while the fireball is ready, brighter while
## the Mage winds one up: the cast leaves for the spot the ring then shows. The ring is as wide as the burst's reach
## (Unified.constants.fireball_radius): what stands inside it is caught.

## The ring's colour while the fireball is ready, and while it winds up (ground_ring.gdshader's `color`).
const READY_COLOR: Color = Color(1.0, 0.55, 0.2, 0.35)
const CASTING_COLOR: Color = Color(1.0, 0.6, 0.25, 0.9)

## Set by the host before _ready, and anew each time the view data changes.
var data: ViewFireballTarget:
	set(value):
		data = value
		if is_node_ready():
			_show()

@onready var _ring: MeshInstance3D = $Ring


func _ready() -> void:
	_ring.scale = Vector3.ONE * Unified.constants.fireball_radius  # the quad is 2 m across
	_show()


func _show() -> void:
	(_ring.material_override as ShaderMaterial).set_shader_parameter(&"color",
		CASTING_COLOR if data.casting else READY_COLOR)
