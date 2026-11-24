extends Node3D

## View_Player (simulation/extension/frame.odin): the host sets it before _ready, and anew each time it changes.
var data: ViewPlayer:
	set(value):
		data = value
		if is_node_ready():
			_paint()

var _tween: Tween

@onready var body: MeshInstance3D = %Body


func _ready() -> void:
	_paint()


# An effect goes on EMITTED (at once, predicted) and is undone on CANCELLED; what must happen once (a score, an
# unlock) goes on CONFIRMED, or a rollback can fire it twice (unified/docs/gameplay.md). The squash is short enough to leave be.
func _sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if event is EventBallThrown and state == UnifiedSession.EVENT_EMITTED:
		if _tween:
			_tween.kill()
		body.scale = Vector3(1.25, 0.8, 1.25)
		_tween = create_tween()
		_tween.tween_property(body, "scale", Vector3.ONE, 0.25)


func _paint() -> void:
	(body.material_override as StandardMaterial3D).albedo_color = data.color
