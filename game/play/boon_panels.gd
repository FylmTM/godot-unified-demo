class_name BoonPanels
extends VBoxContainer
## The HUD's boon panels at the lift's bottom: a BoonPanel for each local hero, side by side, and over them a line
## with the lift's countdown (BOON_TIMEOUT_S from the choosing's start, at the shown game time) that says, once every
## local pick is taken, whom the party waits for ("Waiting for Mara").
##
## They open when the choosing is certain: the lift's Choosing event CONFIRMED (a prediction of it a rollback takes
## back never shows a panel). A player whose session starts while the party chooses (a late joiner, a rejoiner) never
## heard that event: the panels open from the HUD data's lift phase as it first shows, the picks already made marked
## from the data's `picked` (the one prediction they take, as the purse takes its start: plan.md, verified session
## data). A local player joining mid-choice gets its panel as it appears in the data. They close when the descent is
## CONFIRMED. Every pick event goes to every panel (BoonPanel.on_pick, whose rule counts CONFIRMED only).

## A local player's panel (game/play/boon_panel.tscn).
@export var panel_scene: PackedScene

## The depth the panels are open for (-1: closed).
var _depth: int = -1
## The HUD data has shown once (the late joiner's opening is asked of its first showing only).
var _seen_data: bool = false

@onready var _session: UnifiedSession = Unified.session
@onready var _status: Label = %Status
@onready var _panels: HBoxContainer = %Panels


func _ready() -> void:
	visible = false
	_session.sim_event.connect(_on_sim_event)
	Unified.data.hud.changed.connect(_on_data_changed)
	_on_data_changed()


func _process(_delta: float) -> void:
	if visible:
		_show_status()


## The open panels, by local player (the walk reads them).
func panels() -> Array[BoonPanel]:
	var open: Array[BoonPanel] = []
	for child: Node in _panels.get_children():
		if child is BoonPanel and not child.is_queued_for_deletion():
			open.append(child as BoonPanel)
	return open


## Opens a panel for each local hero (the choosing at the HUD data's depth), unless they are open for it already.
func open_panels() -> void:
	_depth = Unified.data.hud.depth
	visible = true
	_add_missing()


## Every panel goes (the descent, confirmed).
func close_panels() -> void:
	_depth = -1
	visible = false
	for panel: BoonPanel in panels():
		panel.queue_free()


func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if event is EventBoonPicked:
		var picked := event as EventBoonPicked
		for panel: BoonPanel in panels():
			panel.on_pick(state, picked.player, picked.boon)
	elif state != UnifiedSession.EVENT_CONFIRMED:
		return
	elif event is EventLift and (event as EventLift).phase == EnumLiftPhase.CHOOSING:
		open_panels()
	elif event is EventDescended:
		close_panels()


## The late joiner's opening (the data's first showing), and a local player joining mid-choice.
func _on_data_changed() -> void:
	var choosing: bool = Unified.data.hud.lift == EnumLiftPhase.CHOOSING
	if not _seen_data and _session.running:
		_seen_data = true
		if choosing:
			open_panels()
			for panel: BoonPanel in panels():
				for hero: DataHudHero in Unified.data.hud.heroes:
					if hero.player != 0 and hero.picked:
						panel.on_pick(UnifiedSession.EVENT_CONFIRMED, hero.player, -1)
	elif _depth >= 0 and choosing:
		_add_missing()


## A panel for every local hero that has none.
func _add_missing() -> void:
	var party: Array[int] = []
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player != 0:
			party.append(hero.player)
	var shown: Array[int] = []
	for panel: BoonPanel in panels():
		shown.append(panel.player)
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player == 0 or not hero.local or shown.has(hero.player):
			continue
		var panel: BoonPanel = panel_scene.instantiate()
		_panels.add_child(panel)
		panel.open(_session.get_local_index(hero.player), hero, party)


## The countdown, and whom the party waits for once every local pick is taken.
func _show_status() -> void:
	var waited: float = (_session.shown_time - Unified.data.hud.lift_since) / Unified.tick_hz
	var left: int = maxi(ceili(Unified.constants.boon_timeout - waited), 0)
	var waiting: Array[int] = []
	var all_taken: bool = true
	for panel: BoonPanel in panels():
		all_taken = all_taken and panel.taken()
		for key: int in panel.waiting_for():
			if not waiting.has(key):
				waiting.append(key)
	var names: PackedStringArray = []
	for key: int in waiting:
		names.append(_session.get_player_name(key))
	if all_taken and not names.is_empty():
		_status.text = "Waiting for %s  (%d s)" % [", ".join(names), left]
	else:
		_status.text = "The lift leaves in %d s" % left
