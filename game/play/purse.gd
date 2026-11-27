class_name Purse
extends VBoxContainer
## The HUD's purse: the party's gold, with a coin's chime and a "+N" rising from where it lay for each pickup. It counts
## a pickup only once it is CONFIRMED (EventLootCollected on the verified timeline), never as predicted: a pickup a
## rollback takes back, or hands to another hero, never moved it, so the purse never counts back and its chime is never
## one that turns out wrong. The world shows the predicted pickup at once instead (the coin gone, a glint: play.gd),
## which costs nothing when a rollback takes it back.
##
## In a live session it shows the `gold` each confirmed pickup carries, as it comes: the purse's total on the verified
## timeline then, not a sum of events (a re-simulation may change an event's fields before it is confirmed: another
## hero's pickup got in first). Confirmed events arrive in tick order, so that total only grows. The HUD data, the
## newest prediction, never moves it but at its seeds, as unified has no verified session data to read (docs/plan.md,
## Needed from unified: verified session data):
## - its start, the data's gold as it first shows and at the data's first change (a continued crypt's, a late
##   joiner's), never lower than what it shows: a prediction in that start holds the purse there until a confirmed
##   total passes it;
## - again once the link recovers (STATUS_CONNECTED after STATUS_RECOVERING): a client caught up by a resync never
##   heard the confirmed pickups of the ticks it skipped, so its count is the data's.
## In a replay every tick is final and a seek or a loop moves the state back and forth, so the purse shows the data's
## gold at every change (the chime and the "+N" still play on each confirmed pickup).
##
## The hoard's gold comes the same way: the descent's CONFIRMED event carries the purse's total with it; and so does a
## life lost (the purse back at the save point's), a run's beginning (an empty purse) and the boss's fall (with a chime
## and its "+N" over where it fell).
##
## on_pickup is the whole rule, a pure function of a pickup's state and fields; the walk drives it with made-up
## EMITTED, CANCELLED and CONFIRMED pickups (game/tools/ui_walk.gd), since a solo session confirms in the frame it
## emits.

## How long a "+N" takes to rise and fade (seconds), how far it rises (pixels of the HUD's canvas), and from how high
## above where the coin lay (metres: about a hero's chest).
const RISE_S: float = 1.0
const RISE_PX: float = 80.0
const FROM_HEIGHT: float = 1.4

## The gold shown.
var _gold: int = 0
## The start was read from the data (live sessions: it is read once, and again after a recovery).
var _seeded: bool = false
## The link is recovering: the next CONNECTED seeds the purse again.
var _recovering: bool = false
## The process frame the chime last played in: the pickups confirmed in one frame chime once.
var _chimed_frame: int = -1

@onready var _gold_label: Label = %Gold
@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	_on_data_changed()
	_seeded = false  # read again at the data's first change: the session's first fill, if the purse showed before it
	Unified.data.hud.changed.connect(_on_data_changed)
	_session.sim_event.connect(_on_sim_event)
	_session.status_changed.connect(_on_status_changed)


## The gold shown (the walks read it).
func gold() -> int:
	return _gold


## A pickup's event in `state` (UnifiedSession.EVENT_*), carrying the purse's total `gold` and the coin's `value`,
## where it lay (`at`): on CONFIRMED alone, the purse shows `gold` (a replay's shows the data's), chimes (once a frame)
## and floats "+`value`" over `at`; EMITTED and CANCELLED change nothing.
func on_pickup(state: UnifiedSession.EventState, gold: int, value: int, at: Vector3) -> void:
	if state != UnifiedSession.EVENT_CONFIRMED:
		return
	if _session.mode != UnifiedSession.MODE_REPLAY:
		_show(gold)
	if Engine.get_process_frames() != _chimed_frame:
		_chimed_frame = Engine.get_process_frames()
		Sfx.play(&"coin")
	_rise(at, value)


## The HUD data changed: a replay's purse is its gold; a live one's takes it only to seed (never lower than shown).
func _on_data_changed() -> void:
	if _session.mode == UnifiedSession.MODE_REPLAY:
		_show(Unified.data.hud.gold)
	elif not _seeded:
		_seeded = true
		_show(maxi(_gold, Unified.data.hud.gold))


## A link that recovered (a resync) seeds the purse again from the data: what it shows is the data's, as it stands.
func _on_status_changed(status: UnifiedSession.Status, _detail: String) -> void:
	if status == UnifiedSession.STATUS_RECOVERING:
		_recovering = true
	elif status == UnifiedSession.STATUS_CONNECTED and _recovering:
		_recovering = false
		_show(Unified.data.hud.gold)


func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if event is EventLootCollected:
		var collected := event as EventLootCollected
		on_pickup(state, collected.gold, collected.value, collected.position)
	elif state != UnifiedSession.EVENT_CONFIRMED or _session.mode == UnifiedSession.MODE_REPLAY:
		return
	elif event is EventDescended:
		_show((event as EventDescended).gold)  # the hoard's gold: the total it carries, as a pickup's
	elif event is EventLifeLost:
		_show((event as EventLifeLost).gold)  # back at the save point's: the purse may count down here alone
	elif event is EventRunBegan:
		_show(0)
	elif event is EventBossDefeated:
		var fell := event as EventBossDefeated
		on_pickup(state, fell.gold, Unified.constants.boss_gold, fell.position)


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
