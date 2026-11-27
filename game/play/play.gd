class_name Play
extends Node3D
## The play scene: the level root the session instances the floor under (its meshes are the crypt), the views root it
## spawns the heroes and the elites under, the bolts' MultiMeshes (the heroes' and the skeleton Mages'), the local
## players' devices (Couch), the camera, the effects, the light, the wall cutaway and the HUD. The session is the app's
## (Game's), already running when this scene loads: this hands it the two roots, which leave with the scene.
##
## It hands every sim event, in each of its states, to the Effects, which show it by the event-state rule (Effects'
## header), and adds what the scene itself owns: a shake as a local hero is hurt (and its plate's HP bar pulses), as a
## fireball bursts, a heaved body lands, the boss's slam strikes and a stage begins (on EMITTED, as soon as predicted);
## and what must be certain, once CONFIRMED: a revive's toast ("X revived Y"), the wipe's banner (the HUD), the
## descent's toast, and the King's fall's toast. A coin's pickup counts in the purse once confirmed (the HUD's Purse),
## and the hoard's gold once the descent is. The crypt fades to black and back as the verified level changes (the
## HUD's fade), and the new floor gets its light (Lighting: its Environment, the vault's ambient following its lit
## braziers) and its walls to cut away (Cutaway); the last floor's effects end with it.
##
## The run: once CONFIRMED, a run's beginning and a life lost say so in a toast (and the HUD counts the felled anew),
## and a run's end shows its results (the HUD's).
##
## The mouse's aim reaches the sim through it, as only a script knows it: just before the session samples (its
## input_wanted, so this frame's sample takes it), the cursor's ray meets a plane at chest height, and the direction
## from the keyboard player's shown hero to that point is that player's input value. Esc, or a pad's Start that the
## Couch left (a pad that plays already), opens the pause menu (PauseMenu: it pauses alone, and is an overlay with a
## Pause for everyone with others), as does the window going to the background in a single-player game (Game's
## pause_wanted). A pad joining, or a guest dropping out, gets its card in the HUD (JoinCards), and the Couch does the
## rest.

## The height of the plane the cursor aims on: a hero's chest, so the hero looks at what the cursor is over.
const AIM_PLANE_HEIGHT: float = 1.2
## A cursor this close to the hero (metres, on the floor) doesn't aim: its direction would swing wildly.
const AIM_DEAD_RADIUS: float = 0.5
## How hard a local hero's hurt shakes the camera (0 to 1), at the player's full screen shake (Settings).
const HURT_SHAKE: float = 0.5
## How hard a fireball's blast shakes the camera (0 to 1), at the player's full screen shake.
const FIREBALL_SHAKE: float = 0.35
## How hard a heaved body's landing shakes the camera (0 to 1), at the player's full screen shake.
const LANDING_SHAKE: float = 0.2
## How hard the boss's slam and its roar shake the camera (0 to 1), at the player's full screen shake.
const SLAM_SHAKE: float = 0.6
const ROAR_SHAKE: float = 0.4

## The pause menu (game/play/pause_menu.tscn), made when it opens.
@export var pause_menu_scene: PackedScene

## Whether the mouse aims for the keyboard's player: once it has moved.
var _mouse_aims: bool = false
## The pause menu while it shows (null: closed).
var _pause_menu: PauseMenu = null
## The Toggle way of holding Interact (Settings.hold_actions), by local index: each local player's latch, its Interact
## presses since the last sample (by device, _input) and whether its hero was hurt since (a local hero's EMITTED hurt).
var _latches: Array[InteractLatch] = []
var _pressed: Array[bool] = []
var _hurt: Array[bool] = []

@onready var _session: UnifiedSession = Unified.session
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _effects: Effects = $Effects
@onready var _level: Node3D = $Level
@onready var _views: Node3D = $Views
@onready var _couch: Couch = $Couch
@onready var _hud: Hud = $Hud
@onready var _menus: CanvasLayer = $Menus
@onready var _lighting: Lighting = $Lighting
@onready var _cutaway: Cutaway = $Cutaway


func _ready() -> void:
	_session.level_root = _level
	_session.view_root = _views
	_session.level_changed.connect(_on_level_changed)
	_session.level_changing.connect(func(_to: int) -> void: _hud.fade_out())
	Game.listen(self, _session.input_wanted, _set_aims)
	_session.sim_event.connect(_on_sim_event)
	_set_flashes()
	Game.listen(self, Settings.changed, func(setting: StringName) -> void:
		if setting == &"flashes":
			_set_flashes())
	_couch.idle_pad_changed.connect(_hud.show_join_hint)
	_hud.show_join_hint(_couch.idle_pad())
	var cards: JoinCards = _hud.join_cards()
	_couch.join_requested.connect(func(device: int) -> void:
		cards.open_join(device, Party.name_of(_couch.next_place()), _remembered_pick()))
	_couch.drop_requested.connect(func(local: int) -> void:
		var player: int = _session.get_local_player_key(local)
		cards.open_drop(local, player, _session.get_local_device(local), _session.get_player_name(player),
			Heroes.class_of(player)))
	cards.join_chosen.connect(_couch.join)
	cards.join_given_up.connect(_couch.give_up)
	cards.drop_chosen.connect(_couch.drop)
	Game.pause_wanted.connect(open_pause_menu)
	var panels: Control = _hud.boon_panels()
	panels.visibility_changed.connect(func() -> void: _camera_rig.bottom_covered = panels.visible)
	if not _session.running and Game.flow == Game.Flow.MENU:
		Game.start_single()  # the scene run on its own (the editor's Run Current Scene)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_aims = true
	if event.is_action_pressed(&"interact") and not event.is_echo():
		for local: int in _session.local_indices:
			if _plays_on(local, event):
				_grow_latches(local)
				_pressed[local] = true


## Whether `event` came from local player `local`'s device: every device for DEVICE_ANY, the keyboard and mouse for
## DEVICE_KEYBOARD, else its pad's.
func _plays_on(local: int, event: InputEvent) -> bool:
	var device: int = _session.get_local_device(local)
	if device == UnifiedSession.DEVICE_ANY:
		return true
	var pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	if device == UnifiedSession.DEVICE_KEYBOARD:
		return not pad
	return pad and event.device == device


## The latch arrays reach local index `local`.
func _grow_latches(local: int) -> void:
	while _latches.size() <= local:
		_latches.append(InteractLatch.new())
		_pressed.append(false)
		_hurt.append(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _session.game_input:
		return  # an overlay holds the game's input: its keys aren't the game's
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		open_pause_menu()


## Settings.flashes where the effects and the views read it: Effects' light pulses, the elites' flash (Flashes.on).
func _set_flashes() -> void:
	_effects.pulses = Settings.flashes
	Flashes.on = Settings.flashes


## Opens the pause menu (it is open already: nothing).
func open_pause_menu() -> void:
	if _pause_menu != null:
		return
	_pause_menu = pause_menu_scene.instantiate()
	_pause_menu.couch = _couch
	_pause_menu.closed.connect(func() -> void:
		_pause_menu = null
		_hud.set_menu_open(false))
	_menus.add_child(_pause_menu)
	_hud.set_menu_open(true)


## The pause menu while it shows (null: closed): the walk reads it.
func pause_menu() -> PauseMenu:
	return _pause_menu


## Every local player's mouse aim, for this frame's sample: toward the cursor for the one who holds the keyboard (or
## every device, while the keyboard and mouse are what was used last: a solo pad player never aims at the cursor
## left where it was), none for the others, and none while game input is off; and its Interact as the Toggle latch
## holds it (InteractLatch: Settings.hold_actions).
func _set_aims() -> void:
	for local: int in _session.local_indices:
		var device: int = _session.get_local_device(local)
		var keyboard: bool = (device == UnifiedSession.DEVICE_KEYBOARD
			or device == UnifiedSession.DEVICE_ANY and Prompts.last_kind == Bindings.Kind.KEYBOARD)
		var aims: bool = keyboard and _mouse_aims and _session.game_input
		Unified.local_input(local).aim = _cursor_aim(local) if aims else Vector2.ZERO
		_grow_latches(local)
		var toggle: bool = Settings.hold_actions == Settings.HoldActions.TOGGLE and _session.game_input
		var held: bool = _latches[local].step(toggle, _pressed[local], _offered(local), _hurt[local])
		Unified.local_input(local).interact = held
		_pressed[local] = false
		_hurt[local] = false


## Whether the HUD offers local player `local`'s hero a revive or a brazier's light now (Hud_Hero.revive, .kindle):
## what the Toggle latch holds Interact for.
func _offered(local: int) -> bool:
	var player: int = _session.get_local_player_key(local)
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player == player:
			return hero.revive != 0 or hero.kindle != 0
	return false


## From local player `local`'s shown hero to where the cursor's ray meets the aim plane, on the floor (x, z); zero
## without a hero, without a hit, or within AIM_DEAD_RADIUS of the hero.
func _cursor_aim(local: int) -> Vector2:
	var hero: Node3D = _session.get_player_view(EnumView.HERO, _session.get_local_player_key(local)) as Node3D
	var camera: Camera3D = get_viewport().get_camera_3d()
	if hero == null or camera == null:
		return Vector2.ZERO
	var cursor: Vector2 = get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, AIM_PLANE_HEIGHT)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
	if hit == null:
		return Vector2.ZERO
	var point: Vector3 = hit
	var aim := Vector2(point.x - hero.global_position.x, point.z - hero.global_position.z)
	return aim if aim.length() >= AIM_DEAD_RADIUS else Vector2.ZERO


## The pick remembered for the party place a joining pad would take (Settings.hero_picks, by local index).
func _remembered_pick() -> int:
	var picks: Array = Settings.hero_picks
	var place: int = _couch.next_place()
	var pick: int = picks[place] if place < picks.size() else EnumClass.ANY
	return pick


## The floor is on screen: the crypt fades back in under its light, the last floor's effects gone and its walls ready
## to be cut away, and the camera frames its hero spawns until a local hero is there.
func _on_level_changed(level_id: int) -> void:
	_lighting.show_level(EnumLevel.name(level_id))
	_effects.clear()
	_cutaway.track(_level)
	_hud.fade_in()
	var sum := Vector3.ZERO
	var count: int = 0
	for marker: Node in Unified.level_markers(_level):
		if marker is HeroSpawn:
			sum += (marker as HeroSpawn).global_position
			count += 1
	if count > 0:
		_camera_rig.fallback = sum / count


## Every sim event to the Effects in each of its states; on its first showing (EMITTED) the shakes and the plate's
## pulse, and what waits until it is certain (CONFIRMED: _on_sim_event_confirmed).
func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	_effects.on_event(event, state)
	if state == UnifiedSession.EVENT_CONFIRMED:
		_on_sim_event_confirmed(event)
	elif state == UnifiedSession.EVENT_EMITTED:
		_on_sim_event_emitted(event)


## The camera's shakes, at the player's screen shake (Settings), and a local hero's hurt on its plate.
func _on_sim_event_emitted(event: UnifiedEvent) -> void:
	if event is EventHeroHurt:
		var player: int = (event as EventHeroHurt).player
		var local: int = _session.get_local_index(player)
		if local >= 0:
			_camera_rig.shake(HURT_SHAKE * Settings.screen_shake)
			_hud.pulse_hurt(player)
			_grow_latches(local)
			_hurt[local] = true  # a blow lets go of the Toggle latch
	elif event is EventFireballBurst:
		_camera_rig.shake(FIREBALL_SHAKE * Settings.screen_shake)
	elif event is EventHeaveLanded:
		_camera_rig.shake(LANDING_SHAKE * Settings.screen_shake)
	elif event is EventBossStage:
		_camera_rig.shake(ROAR_SHAKE * Settings.screen_shake)
	elif event is EventBossSlam:
		_camera_rig.shake(SLAM_SHAKE * Settings.screen_shake)


## What must not be taken back once shown, on its CONFIRMED showing: a revive's toast, and the wipe's banner (a revive
## or a wipe a rollback undid would have hung for nothing); the run's beginning, a life lost and the run's end; and
## with Settings.captions on, the caption of what is heard more than seen (Captions).
func _on_sim_event_confirmed(event: UnifiedEvent) -> void:
	var caption: String = Captions.toast(event, _session, Settings.captions)
	if caption != "":
		Game.toast(caption)
	if event is EventHeroRevived:
		var revived := event as EventHeroRevived
		var risen: String = _session.get_player_name(revived.player)
		if revived.by == 0:  # nobody's hands: the Pit's lull raises the downed
			Game.toast("%s is up again" % risen)
		else:
			Game.toast("%s revived %s" % [_session.get_player_name(revived.by), risen])
	elif event is EventPartyWiped:
		_hud.show_wipe()
	elif event is EventDescended:
		Game.toast("Down to depth %d with the hoard" % (event as EventDescended).depth)
	# The run
	elif event is EventRunBegan:
		var began := event as EventRunBegan
		var mode: String = "The Pit" if began.mode == EnumMode.PIT else "The crypt"
		Game.toast("%s opens · %s" % [mode, EnumDifficulty.name(began.difficulty).capitalize()])
		_hud.count_anew()
	elif event is EventLifeLost:
		var lives: int = (event as EventLifeLost).lives
		if lives > 0:
			Game.toast("A life lost: %s left" % ("1 life" if lives == 1 else "%d lives" % lives))
		_hud.count_anew()
	elif event is EventRunEnded:
		_hud.show_results(event as EventRunEnded)
	elif event is EventBossDefeated:
		Game.toast("The Bone King has fallen")
