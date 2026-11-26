class_name Hud
extends Control
## The HUD, quiet in the corners so the crypt keeps the middle: a plate for each local hero (its player's name, its
## class and health, or that it is down), the surges faced, the skeletons up and the felled (a save's tally included),
## a game with friends' code or address and its players (SessionPanel), the co-op pause's banner naming who paused and
## how to reach the menu (to resume), the join and drop cards, and "[Start] Join the game" while a connected pad plays
## nobody and the couch has room. Each plate carries its player's control hints, in the glyphs of that player's device,
## when Settings.hints says. Over the crypt, a "[E] Revive" prompt hangs above a downed ally for each local hero whose
## Interact would revive them now (Hud_Hero.revive: the rules' revive_target), in that player's glyphs; and when the
## whole party has fallen (a CONFIRMED Event_Party_Wiped: show_wipe), a banner says so until a hero is up again (the
## floor's restart, a revive, a joiner). Nothing on it takes a click or the focus: Space and a pad's A stay the game's.
##
## What it shows is session data (Unified.data.hud), the newest prediction, which a rollback may change and the next
## frame puts right. The felled are a count, which must never take one back: it shows the most the data has said this
## game (a kill a rollback took back is counted again by the next real one, never shown falling).

## How high above a downed ally's feet its revive prompt hangs (metres: over the head of the hero who would revive it,
## standing beside it).
const REVIVE_PROMPT_HEIGHT: float = 2.6

var _kills: int = 0
## The party's fall was confirmed and no hero is up since (the banner shows).
var _wiped: bool = false
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
@onready var _wiped_banner: Control = %Wiped
@onready var _wiped_text: Label = %WipedText
@onready var _revive_prompts: Control = %RevivePrompts


func _ready() -> void:
	_banner_width = _paused_text.custom_minimum_size.x
	Unified.data.hud.changed.connect(_show_data)
	for plate: Control in [_heroes, _crypt, _session_panel]:
		plate.resized.connect(_keep_clear_of_plates)
		plate.visibility_changed.connect(_keep_clear_of_plates)
	get_viewport().size_changed.connect(_keep_clear_of_plates)
	_show_data()
	_keep_clear_of_plates.call_deferred()


## The toasts, the co-op pause's and the wipe's banners and the link plate keep to the lane between the hero plates and
## the counts (with the session panel under them), the toasts above the banners; the join cards hang below the counts
## and the panel.
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
	_wiped_text.theme_type_variation = _paused_text.theme_type_variation
	_wiped_text.custom_minimum_size.x = _paused_text.custom_minimum_size.x
	lane.centre(_wiped_banner)
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
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player != 0 and not hero.down:
			_wiped = false  # a hero up: the floor restarted, or a revive or a joiner stopped the wipe
	_wiped_banner.visible = _wiped and not _paused.visible and not _menu_open


func _process(_delta: float) -> void:
	_place_revive_prompts()


## The whole party has fallen (a CONFIRMED Event_Party_Wiped): the banner shows until the HUD's data has a hero up.
func show_wipe() -> void:
	_wiped = true
	_show_data()


## Each local hero's "[E] Revive" over the ally its Interact would revive (Hud_Hero.revive), in that player's glyphs,
## above the ally's view on screen; two local heroes at one ally stack their prompts. Placed every frame, as the camera
## and the views move between the HUD's data changes.
func _place_revive_prompts() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var prompts: Array[Node] = _revive_prompts.get_children()
	var shown: int = 0
	var stacked: Dictionary[int, int] = {}
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player == 0 or not hero.local or hero.revive == 0 or camera == null or shown >= prompts.size():
			continue
		var ally := Unified.session.get_player_view(EnumView.HERO, hero.revive) as Node3D
		var above: Vector3 = ally.global_position + Vector3.UP * REVIVE_PROMPT_HEIGHT if ally != null else Vector3.ZERO
		if ally == null or camera.is_position_behind(above):
			continue
		var prompt := prompts[shown] as ActionPrompt
		shown += 1
		var local: int = Unified.session.get_local_index(hero.player)
		if prompt.local != local:
			prompt.local = local
			prompt.refresh()
		prompt.visible = true
		prompt.size = prompt.get_combined_minimum_size()
		var on_screen: Vector2 = get_global_transform_with_canvas().affine_inverse() * camera.unproject_position(above)
		var row: int = stacked.get(hero.revive, 0)
		stacked[hero.revive] = row + 1
		prompt.position = on_screen - Vector2(prompt.size.x / 2.0, prompt.size.y * (row + 1))
	for i: int in range(shown, prompts.size()):
		(prompts[i] as Control).visible = false


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
