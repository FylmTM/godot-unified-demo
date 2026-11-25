class_name Hud
extends Control
## The HUD, quiet in the corners so the crypt keeps the middle: a plate for each local hero (its class and health, or
## that it is down), the skeletons up and the kills, the co-op pause's banner, and "[Start] Join the game" while a
## connected pad plays nobody. Each plate carries its player's control hints, in the glyphs of that player's device.
## Nothing on it takes a click or the focus: Space and a pad's A stay the game's.
##
## What it shows of the moment (the heroes, the skeletons up, the pause) is session data (Unified.data.hud), the newest
## prediction, which a rollback may change and the next frame puts right. The kills are a count, which must never take
## one back: it counts each minion's death once its tick is CONFIRMED (a session's own kills, from when this HUD began).

var _kills: int = 0

@onready var _heroes: VBoxContainer = %Heroes
@onready var _skeletons: Label = %Skeletons
@onready var _kills_label: Label = %Kills
@onready var _paused: Control = %Paused
@onready var _join_hint: Control = %JoinHint
@onready var _join_prompt: ActionPrompt = %JoinPrompt
@onready var _join_cards: JoinCards = %JoinCards


func _ready() -> void:
	Unified.data.hud.changed.connect(_show_data)
	Unified.session.sim_event.connect(_on_sim_event)
	_show_data()


## A plate per local hero (in slot order; the spare plates hide), the crypt's counts, and the pause.
func _show_data() -> void:
	var plates: Array[Node] = _heroes.get_children()
	var shown: int = 0
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player != 0 and hero.local and shown < plates.size():
			(plates[shown] as HeroPlate).show_hero(hero, Unified.session.get_local_index(hero.player))
			shown += 1
	for i: int in plates.size():
		(plates[i] as Control).visible = i < shown
	_skeletons.text = str(Unified.data.hud.minions)
	_kills_label.text = str(_kills)
	_paused.visible = Unified.data.hud.paused


## The cards a pad picks its hero on to join, or confirms it drops out.
func join_cards() -> JoinCards:
	return _join_cards


## Shows the join hint to pad `device` ("[Start] Join the game" in its glyphs), or hides it (-1: every connected
## pad plays; the Couch says which pad is idle).
func show_join_hint(device: int) -> void:
	_join_hint.visible = device >= 0
	if device >= 0:
		_join_prompt.pad_device = device
		_join_prompt.refresh()


func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if event is EventMinionDied and state == UnifiedSession.EVENT_CONFIRMED:
		_kills += 1
		_show_data()
