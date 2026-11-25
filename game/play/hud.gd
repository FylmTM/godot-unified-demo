class_name Hud
extends Control
## The HUD, quiet in the corners so the crypt keeps the middle: a plate for each local hero (its player's name, its
## class and health, or that it is down), the surges faced, the skeletons up and the felled (a save's tally included),
## the co-op pause's banner naming who paused, the join and drop cards, and "[Start] Join the game" while a connected
## pad plays nobody and the couch has room. Each plate carries its player's control hints, in the glyphs of that
## player's device, when Settings.hints says. Nothing on it takes a click or the focus: Space and a pad's A stay the
## game's.
##
## What it shows is session data (Unified.data.hud), the newest prediction, which a rollback may change and the next
## frame puts right. The felled are a count, which must never take one back: it shows the most the data has said this
## game (a kill a rollback took back is counted again by the next real one, never shown falling).

var _kills: int = 0

@onready var _heroes: VBoxContainer = %Heroes
@onready var _skeletons: Label = %Skeletons
@onready var _kills_label: Label = %Kills
@onready var _paused: Control = %Paused
@onready var _paused_text: Label = %PausedText
@onready var _surges: Label = %Surges
@onready var _join_hint: Control = %JoinHint
@onready var _join_prompt: ActionPrompt = %JoinPrompt
@onready var _join_cards: JoinCards = %JoinCards


func _ready() -> void:
	Unified.data.hud.changed.connect(_show_data)
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
	_surges.text = str(Unified.data.hud.surges)
	_skeletons.text = str(Unified.data.hud.minions)
	_kills = maxi(_kills, Unified.data.hud.kills)
	_kills_label.text = str(_kills)
	_paused.visible = Unified.data.hud.paused
	var pauser: String = Unified.session.get_player_name(Unified.data.hud.paused_by)
	_paused_text.text = "Paused by %s" % pauser if pauser != "" else "Paused"


## The cards a pad picks its hero on to join, or confirms it drops out.
func join_cards() -> JoinCards:
	return _join_cards


## Shows the join hint to pad `device` ("[Start] Join the game" in its glyphs), or hides it (-1: every connected
## pad plays; the Couch says which pad is idle).
func show_join_hint(device: int) -> void:
	_join_hint.visible = device >= 0
	if device >= 0:
		_join_prompt.device = device
		_join_prompt.refresh()

