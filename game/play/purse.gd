class_name Purse
extends VBoxContainer
## The HUD's purse: the party's gold, with a coin's chime and a "+N" rising from where it lay for each pickup. It counts
## a pickup only once it is CONFIRMED (EventLootCollected on the verified timeline), never as predicted: a pickup a
## rollback takes back, or hands to another hero, never moved it, so the purse never counts back and its chime is never
## one that turns out wrong. The world shows the predicted pickup at once instead (the coin gone, a glint: play.gd),
## which costs nothing when a rollback takes it back.
##
## What it shows is the `gold` the last confirmed pickup carries, the purse's total on the verified timeline then, not
## a sum of events: a re-simulation may change an event's fields before it is confirmed (another hero's pickup got in
## first), and the confirmed total is right whatever came before. Confirmed events arrive in tick order, so it only
## grows. Its start is the HUD data's gold as the purse first shows (a continued crypt's, a late joiner's), the one time
## it reads the data: the data is the newest prediction, and unified has no verified session data to start from
## (docs/plan.md, Needed from unified: verified session data). Should that start hold a pickup still unconfirmed, the
## purse holds there until the confirmed total passes it, rather than counting back.

## How long a "+N" takes to rise and fade (seconds), how far it rises (pixels of the HUD's canvas), and from how high
## above where the coin lay (metres: about a hero's chest).
const RISE_S: float = 1.0
const RISE_PX: float = 80.0
const FROM_HEIGHT: float = 1.4

## The gold shown.
var _gold: int = 0
## The process frame the chime last played in: the pickups confirmed in one frame chime once.
var _chimed_frame: int = -1

@onready var _gold_label: Label = %Gold


func _ready() -> void:
	_start_from_data()
	Unified.data.hud.changed.connect(_start_from_data, CONNECT_ONE_SHOT)  # the session's first data, if not here yet
	Unified.session.sim_event.connect(_on_sim_event)


## The gold shown (the walks read it).
func gold() -> int:
	return _gold


## The purse's start: the HUD data's gold, read as it first shows and once more at its first change (the session's
## first fill, when the purse showed before it), never lower than what it shows.
func _start_from_data() -> void:
	_show(maxi(_gold, Unified.data.hud.gold))


func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state != UnifiedSession.EVENT_CONFIRMED or not event is EventLootCollected:
		return
	var collected := event as EventLootCollected
	_show(maxi(_gold, collected.gold))
	if Engine.get_process_frames() != _chimed_frame:
		_chimed_frame = Engine.get_process_frames()
		Sfx.play(&"coin")
	_rise(collected.position, collected.value)


func _show(gold: int) -> void:
	_gold = gold
	_gold_label.text = str(gold)


## A "+`value`" rising and fading from above `at` (a point in the world), following it as the camera moves.
func _rise(at: Vector3, value: int) -> void:
	var gain := Label.new()
	gain.text = "+%d" % value
	gain.theme_type_variation = &"Gain"
	gain.top_level = true  # placed on the canvas, not by the purse's column
	add_child(gain)
	_place(0.0, gain, at)
	var rise: Tween = gain.create_tween()
	rise.tween_method(_place.bind(gain, at), 0.0, 1.0, RISE_S)
	rise.tween_callback(gain.queue_free)


## Places a rising "+N" `done` of the way through its rise (0 to 1): above `at` as the camera sees it, up and fading.
func _place(done: float, gain: Label, at: Vector3) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var above: Vector3 = at + Vector3(0, FROM_HEIGHT, 0)
	gain.visible = camera != null and not camera.is_position_behind(above)
	if not gain.visible:
		return
	var point: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * camera.unproject_position(above)
	gain.position = point - gain.size / 2.0 - Vector2(0, RISE_PX * done)
	gain.modulate.a = 1.0 - done * done
