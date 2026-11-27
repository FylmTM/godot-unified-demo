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
## floor's restart, a revive, a joiner). A "[E] Haul" prompt hangs over the hoard's handle a local hero's Interact would
## take (Hud_Hero.haul: the rules' haul_target), and a line at the bottom says "The hoard must be wholly on the lift"
## while it rests hanging over the deck's edge (Data_Hud.overhang). At the lift's bottom the boon panels show
## (BoonPanels). A "[E] Light" prompt hangs over the brazier a local hero's Interact would kindle (Hud_Hero.kindle: the
## rules' kindle_target), and while the boss is awake its bar shows at the bottom (the top's lane is the toasts' and the
## banners'): its health, and while it is warded how many braziers are lit of how many break the ward
## (Data_Hud.boss_*). As the verified
## level changes (a descent, a wipe's restart) the crypt fades to black and back (fade_out, fade_in: play.gd). Nothing
## on it takes a click or the focus: Space and a pad's A stay the game's.
##
## The run: in the hub a banner over the crypt's lift names the run its shrines set ("The Crypt · Hard"), and a
## "[E] Turn" prompt hangs over the shrine a local hero's Interact would turn (Hud_Hero.shrine: the rules'
## shrine_target); during a run the counts carry its life pips (lives left of the lives it began with); when the run
## ends (a CONFIRMED Event_Run_Ended: show_results) a panel shows its tally until the party is back in the hub.
##
## What it shows is session data (Unified.data.hud), the newest prediction, which a rollback may change and the next
## frame puts right. The felled are a count, which must never take one back: it shows the most the data has said this
## game (a kill a rollback took back is counted again by the next real one, never shown falling).
##
## The party's gold is the Purse's (purse.gd), counted from confirmed pickups rather than from this data.

## How high above a downed ally's feet its revive prompt hangs (metres: over the head of the hero who would revive it,
## standing beside it).
const REVIVE_PROMPT_HEIGHT: float = 2.6
## How far above a hoard's handle its haul prompt hangs (metres).
const HAUL_PROMPT_HEIGHT: float = 1.0
## How high above a brazier's foot its light prompt hangs (metres: under its bowl, at a hero's head).
const KINDLE_PROMPT_HEIGHT: float = 2.4
## How long the fade to black takes as the verified level changes, and back once the new one shows (seconds).
const FADE_OUT_S: float = 0.25
const FADE_IN_S: float = 0.6
## How far above the hub lift's deck its banner hangs, and above a shrine its prompt (metres).
const BANNER_HEIGHT: float = 3.5
const SHRINE_PROMPT_HEIGHT: float = 2.2
## A life pip's size (pixels of the HUD's canvas), and its colours: a life left, a life gone.
const PIP_SIZE: float = 18.0
const PIP_LEFT: Color = Color(0.96, 0.74, 0.36)
const PIP_GONE: Color = Color(1.0, 1.0, 1.0, 0.16)

var _kills: int = 0
## The party's fall was confirmed and no hero is up since (the banner shows).
var _wiped: bool = false
## The pause menu shows (it says the pause itself: the banner hides).
var _menu_open: bool = false
## The banner's text width when the lane allows it (the scene's).
var _banner_width: float = 0.0
## The run's end was confirmed and the party isn't back in the hub yet (the results show).
var _ended: bool = false

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
@onready var _haul_prompts: Control = %HaulPrompts
@onready var _fade: ColorRect = %Fade
@onready var _boon_panels: BoonPanels = %BoonPanels
@onready var _overhang: Control = %Overhang
@onready var _lives: Control = %Lives
@onready var _live_pips: HBoxContainer = %LivePips
@onready var _run_banner: Control = %RunBanner
@onready var _run_banner_text: Label = %RunBannerText
@onready var _shrine_prompts: Control = %ShrinePrompts
@onready var _results: Control = %Results
@onready var _results_heading: Label = %ResultsHeading
@onready var _results_line: Label = %ResultsLine
@onready var _results_stats: Label = %ResultsStats
@onready var _kindle_prompts: Control = %KindlePrompts
@onready var _boss_bar: Control = %BossBar
@onready var _boss_health: ProgressBar = %BossHealth
@onready var _ward: Label = %Ward


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
	_overhang.visible = Unified.data.hud.overhang and not _menu_open
	_show_run()
	_wiped_banner.visible = _wiped and not _paused.visible and not _menu_open and not _results.visible
	_show_boss()


func _process(_delta: float) -> void:
	_place_revive_prompts()
	_place_haul_prompts()
	_place_run_banner()
	_place_shrine_prompts()
	_place_kindle_prompts()


## The verified level is changing (the session's level_changing): the crypt fades to black.
func fade_out() -> void:
	_fade_to(1.0, FADE_OUT_S)


## The new level shows (level_changed): the crypt fades back in, from however dark the fade got.
func fade_in() -> void:
	_fade_to(0.0, FADE_IN_S)


## The boon panels (the walks drive them).
func boon_panels() -> BoonPanels:
	return _boon_panels


func _fade_to(alpha: float, seconds: float) -> void:
	var fade: Tween = _fade.create_tween()
	fade.tween_property(_fade, ^"color:a", alpha, seconds)


## Each local hero's "[E] Haul" over the hoard's handle its Interact would take (Hud_Hero.haul), in that player's
## glyphs; two at one handle stack. Placed every frame, as the camera and the chest move between the data's changes.
func _place_haul_prompts() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var hoard := Unified.session.get_view(EnumView.HOARD, 0) as HoardView
	var prompts: Array[Node] = _haul_prompts.get_children()
	var shown: int = 0
	var stacked: Dictionary[int, int] = {}
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player == 0 or not hero.local or hero.haul == EnumHaulHandle.NONE or hoard == null or camera == null:
			continue
		var above: Vector3 = hoard.handle_position(hero.haul) + Vector3.UP * HAUL_PROMPT_HEIGHT
		if camera.is_position_behind(above) or shown >= prompts.size():
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
		var row: int = stacked.get(hero.haul, 0)
		stacked[hero.haul] = row + 1
		prompt.position = on_screen - Vector2(prompt.size.x / 2.0, prompt.size.y * (row + 1))
	for i: int in range(shown, prompts.size()):
		(prompts[i] as Control).visible = false


## The boss's bar while it is awake (Data_Hud.boss_hp_max > 0): its health, and while warded the braziers it waits on.
func _show_boss() -> void:
	var hud: DataHud = Unified.data.hud
	_boss_bar.visible = hud.boss_hp_max > 0 and not _menu_open
	if not _boss_bar.visible:
		return
	_boss_health.max_value = hud.boss_hp_max
	_boss_health.value = hud.boss_hp
	_ward.visible = hud.boss_warded
	_ward.text = "Warded: light %d of %d braziers" % [mini(hud.ward_lit, hud.ward_need), hud.ward_need]


## Each local hero's "[E] Light" over the brazier its Interact would kindle (Hud_Hero.kindle), in that player's glyphs;
## two at one brazier stack. Placed every frame, as the camera moves between the data's changes.
func _place_kindle_prompts() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var prompts: Array[Node] = _kindle_prompts.get_children()
	var shown: int = 0
	var stacked: Dictionary[int, int] = {}
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player == 0 or not hero.local or hero.kindle == 0 or camera == null or shown >= prompts.size():
			continue
		var brazier := Unified.session.get_view(EnumView.BRAZIER, hero.kindle) as Node3D
		var above: Vector3 = brazier.global_position + Vector3.UP * KINDLE_PROMPT_HEIGHT if brazier != null else Vector3.ZERO
		if brazier == null or camera.is_position_behind(above):
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
		var row: int = stacked.get(hero.kindle, 0)
		stacked[hero.kindle] = row + 1
		prompt.position = on_screen - Vector2(prompt.size.x / 2.0, prompt.size.y * (row + 1))
	for i: int in range(shown, prompts.size()):
		(prompts[i] as Control).visible = false


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

## The run's end, CONFIRMED (play.gd): the results panel shows its tally (`ended`'s) until the party is back in the hub.
func show_results(ended: EventRunEnded) -> void:
	var time: String = _clock(float(ended.ticks) / Unified.tick_hz)
	if ended.mode == EnumMode.PIT:
		_results_heading.text = "The Pit: %d %s" % [ended.surges, "wave" if ended.surges == 1 else "waves"]
		_results_stats.text = "%d felled · %d gold · %s" % [ended.kills, ended.gold, time]
	else:
		_results_heading.text = "The crypt is yours" if ended.won else "The run is over"
		_results_stats.text = "Depth %d · %d gold · %d felled · %d surges · %s" % [ended.depth, ended.gold,
			ended.kills, ended.surges, time]
	_results_line.text = _run_name()
	_ended = true
	_show_data()


## A run began, or a life was lost (CONFIRMED, play.gd): the felled count from the data again (a new run's start, or
## the save point's), never holding the higher count it showed before.
func count_anew() -> void:
	_kills = 0
	_show_data()


## The run as its banner and results name it: "The Crypt · Normal", "The Pit · Hard".
func _run_name() -> String:
	var hud: DataHud = Unified.data.hud
	var mode: String = "The Pit" if hud.mode == EnumMode.PIT else "The Crypt"
	return "%s · %s" % [mode, EnumDifficulty.name(hud.difficulty).capitalize()]


## Seconds as the results read them: "12:04".
func _clock(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), floori(seconds) % 60]


## The run's parts of the HUD: the life pips during a run, the banner's text in the hub, the results while they hold.
func _show_run() -> void:
	var hud: DataHud = Unified.data.hud
	var in_hub: bool = hud.run == EnumRunPhase.HUB
	if in_hub:
		_ended = false
	_results.visible = _ended and not _menu_open
	_run_banner_text.text = _run_name()
	_lives.visible = not in_hub and hud.lives_max > 0
	while _live_pips.get_child_count() < hud.lives_max:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var round_box := StyleBoxFlat.new()
		round_box.set_corner_radius_all(int(PIP_SIZE / 2.0))
		pip.add_theme_stylebox_override(&"panel", round_box)
		_live_pips.add_child(pip)
	for i: int in _live_pips.get_child_count():
		var pip := _live_pips.get_child(i) as Panel
		pip.visible = i < hud.lives_max
		(pip.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color = PIP_LEFT if i < hud.lives else PIP_GONE


## The hub's banner over its lift's deck, as the camera sees it, kept inside the view (the deck may be off screen while
## the camera frames the party); hidden out of the hub, under a menu, or with the deck behind the camera.
func _place_run_banner() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var lift := Unified.session.get_view(EnumView.LIFT, 0) as Node3D
	var shown: bool = Unified.data.hud.run == EnumRunPhase.HUB and not _menu_open and lift != null and camera != null
	if shown:
		var above: Vector3 = lift.global_position + Vector3.UP * BANNER_HEIGHT
		shown = not camera.is_position_behind(above)
		if shown:
			_run_banner.size = _run_banner.get_combined_minimum_size()
			var at: Vector2 = get_global_transform_with_canvas().affine_inverse() * camera.unproject_position(above)
			var room: Vector2 = size - _run_banner.size - Vector2(Lane.MARGIN, Lane.MARGIN)
			at -= Vector2(_run_banner.size.x / 2.0, _run_banner.size.y)
			_run_banner.position = at.clamp(Vector2(Lane.MARGIN, Lane.MARGIN), room.max(Vector2.ZERO))
	_run_banner.visible = shown


## Each local hero's "[E] Turn" over the shrine its Interact would turn (Hud_Hero.shrine), in that player's glyphs;
## two at one shrine stack.
func _place_shrine_prompts() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var prompts: Array[Node] = _shrine_prompts.get_children()
	var shown: int = 0
	var stacked: Dictionary[int, int] = {}
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player == 0 or not hero.local or hero.shrine == 0 or camera == null or shown >= prompts.size():
			continue
		var shrine := Unified.session.get_view(EnumView.SHRINE, hero.shrine) as Node3D
		if shrine == null:
			continue
		var above: Vector3 = shrine.global_position + Vector3.UP * SHRINE_PROMPT_HEIGHT
		if camera.is_position_behind(above):
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
		var row: int = stacked.get(hero.shrine, 0)
		stacked[hero.shrine] = row + 1
		prompt.position = on_screen - Vector2(prompt.size.x / 2.0, prompt.size.y * (row + 1))
	for i: int in range(shown, prompts.size()):
		(prompts[i] as Control).visible = false
