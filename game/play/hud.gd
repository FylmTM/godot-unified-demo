class_name Hud
extends Control
## The HUD, quiet in the corners so the crypt keeps the middle: a plate for each local hero (its player's name, its
## class and health, or that it is down), the surges faced, the skeletons up and the felled (a save's tally included),
## a game with friends' code or address and its players (SessionPanel), the co-op pause's banner naming who paused and
## how to reach the menu (to resume), the join and drop cards, and "[Start] Join the game" while a connected pad plays
## nobody and the couch has room. Each plate carries its player's control hints, in the glyphs of that player's device,
## when Settings.hints says. Nothing on it takes a click or the focus: Space and a pad's A stay the game's.
##
## What it shows is session data (Unified.data.hud), the newest prediction, which a rollback may change and the next
## frame puts right. The felled are a count, which must never take one back: it shows the most the data has said this
## game (a kill a rollback took back is counted again by the next real one, never shown falling).
##
## The party's gold is the Purse's (purse.gd), counted from confirmed pickups rather than from this data.

var _kills: int = 0
## The pause menu shows (it says the pause itself: the banner hides).
var _menu_open: bool = false
## The banner's text width when the lane allows it (the scene's).
var _banner_width: float = 0.0

@onready var _heroes: VBoxContainer = %Heroes
@onready var _crypt: Control = %Crypt
@onready var _session_panel: Control = %SessionPanel
@onready var _skeletons: Label = %Skeletons
@onready var _kills_label: Label = %Kills
@onready var _paused: Control = %Paused
@onready var _paused_text: NameLabel = %PausedText
@onready var _surges: Label = %Surges
@onready var _join_hint: Control = %JoinHint
@onready var _join_prompt: ActionPrompt = %JoinPrompt
@onready var _join_cards: JoinCards = %JoinCards


func _ready() -> void:
	_banner_width = _paused_text.custom_minimum_size.x
	Unified.data.hud.changed.connect(_show_data)
	for plate: Control in [_heroes, _crypt, _session_panel]:
		plate.resized.connect(_keep_clear_of_plates)
		plate.visibility_changed.connect(_keep_clear_of_plates)
	get_viewport().size_changed.connect(_keep_clear_of_plates)
	_show_data()
	_keep_clear_of_plates.call_deferred()


## The toasts, the co-op pause's banner and the link plate keep to the lane between the hero plates and the counts
## (with the session panel under them), the toasts above the banner; the join cards hang below the counts and the
## panel.
func _keep_clear_of_plates() -> void:
	var right: float = _crypt.get_global_rect().position.x
	var bottom: float = _crypt.get_global_rect().end.y
	if _session_panel.visible:
		right = minf(right, _session_panel.get_global_rect().position.x)
		bottom = _session_panel.get_global_rect().end.y
	var lane := Lane.new(_heroes.get_global_rect().end.x, right)
	var room: float = lane.width() - _paused.get_theme_stylebox(&"panel").get_minimum_size().x
	_paused_text.theme_type_variation = &"Heading" if room >= _banner_width else &"HudText"  # a narrow lane: smaller
	_paused_text.custom_minimum_size.x = minf(_banner_width, room)
	lane.centre(_paused)
	Game.keep_in_lane(lane, _paused.position.y - Lane.MARGIN)
	_join_cards.keep_below(bottom)


## A plate per local hero (in slot order; the spare plates hide), the crypt's counts, and the pause.
func _show_data() -> void:
	var plates: Array[Node] = _heroes.get_children().filter(func(child: Node) -> bool: return child is HeroPlate)
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
	_paused.visible = Unified.data.hud.paused and not _menu_open
	var pauser: String = Unified.session.get_player_name(Unified.data.hud.paused_by)
	_paused_text.show_name("Paused by " if pauser != "" else "Paused", pauser)


## The pause menu opened (`open`) or closed: the co-op pause's banner hides under it.
func set_menu_open(open: bool) -> void:
	_menu_open = open
	_show_data()


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
