class_name PurseWatch
extends RefCounted
## Watches the HUD's purse (game/play/purse.gd) through a session, for the walks: it may change only in a frame in which
## a pickup's CONFIRMED event arrived (or a descent's, which brings the hoard's gold), and never go down, whatever the
## prediction did meanwhile. It counts the pickups' event states too, so a walk on a bad link can say a misprediction
## happened (a CANCELLED pickup: one a rollback took back) and the purse held through it.
##
## The check runs at the start of each frame (SceneTree.process_frame), before the session delivers that frame's
## events, so it judges the change since the last check against the events delivered since then. The purse is read
## through `gold()` by name: a tool script compiles before the autoloads the purse's script names exist.

## What went wrong, a line each (empty: the purse kept the rule).
var problems: Array[String] = []
## The pickups' events seen, by state.
var emitted: int = 0
var confirmed: int = 0
var cancelled: int = 0
## How many times the purse changed.
var changes: int = 0

var _purse: Control
var _session: UnifiedSession
var _shown: int = 0
## A pickup's CONFIRMED event arrived since the last check.
var _confirmed_since: bool = false


func _init(purse: Control, session: UnifiedSession) -> void:
	_purse = purse
	_session = session
	_shown = gold_of(purse)
	session.sim_event.connect(_on_sim_event)
	(Engine.get_main_loop() as SceneTree).process_frame.connect(_check)


## Stops watching (the purse leaves with its scene: stop first).
func stop() -> void:
	_check()
	_session.sim_event.disconnect(_on_sim_event)
	(Engine.get_main_loop() as SceneTree).process_frame.disconnect(_check)


## The counts, for a step's line.
func summary() -> String:
	return "%d changes; pickups %d emitted, %d confirmed, %d cancelled" % [changes, emitted, confirmed, cancelled]


## The gold the purse `purse` (the HUD's %Purse) shows.
static func gold_of(purse: Control) -> int:
	var gold: int = purse.call(&"gold")
	return gold


func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if event is EventDescended and state == UnifiedSession.EVENT_CONFIRMED:
		_confirmed_since = true  # the hoard's gold, carried by the descent's total
	if not event is EventLootCollected:
		return
	match state:
		UnifiedSession.EVENT_EMITTED:
			emitted += 1
		UnifiedSession.EVENT_CONFIRMED:
			confirmed += 1
			_confirmed_since = true
		UnifiedSession.EVENT_CANCELLED:
			cancelled += 1


func _check() -> void:
	if not is_instance_valid(_purse):
		return
	var gold: int = gold_of(_purse)
	if gold != _shown:
		changes += 1
		if gold < _shown:
			problems.append("the purse went down, from %d to %d" % [_shown, gold])
		if not _confirmed_since:
			problems.append("the purse changed from %d to %d with no confirmed pickup or descent" % [_shown, gold])
	_shown = gold
	_confirmed_since = false
