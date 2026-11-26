class_name Play
extends Node3D
## The play scene: the level root the session instances the floor under (its meshes are the crypt), the views root it
## spawns the heroes and the elites under, the bolts' MultiMeshes (the heroes' and the skeleton Mages'), the local
## players' devices (Couch), the camera, the effects, the crypt's environment and the HUD. The session is the app's
## (Game's), already running when this scene loads: this hands it the two roots, which leave with the scene. It turns
## the sim's events into effects as soon as they are predicted (EMITTED): sparks on a hit (a skeleton's, an elite's, a
## bone bolt's; and dust where a guard breaks), a bolt's burst, a crossbow's tracer (from the crossbow as drawn to where
## the sim's shot ended), dust where a prop lands hard, and a shake when a local hero is hurt; a shield's clang and
## sparks, a fireball's blast (with a shake), a hero going down. What must be certain shows once CONFIRMED: a revive's
## chime and its toast ("X revived Y"), and the wipe's banner (the HUD). A coin picked up glints as predicted too (its
## coin gone with it, as the state has it); the purse counts it once confirmed (the HUD's Purse).
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
## Where on a skeleton its hit's sparks fly from, above its feet.
const HIT_HEIGHT: float = 1.1
## Where on an elite its hit's sparks fly from, above its feet (a Warrior's shield, struck).
const ELITE_HIT_HEIGHT: float = 1.3
## A prop landing faster than this (metres per second) raises dust.
const DUST_SPEED: float = 5.0
## How hard a local hero's hurt shakes the camera (0 to 1), at the player's full screen shake (Settings).
const HURT_SHAKE: float = 0.5
## How hard a fireball's blast shakes the camera (0 to 1), at the player's full screen shake.
const FIREBALL_SHAKE: float = 0.35
## Where a picked-up coin's glint shines from, above where it lay (its hover: game/views/coin.gdshader).
const GLINT_HEIGHT: float = 0.4

## The pause menu (game/play/pause_menu.tscn), made when it opens.
@export var pause_menu_scene: PackedScene

## Whether the mouse aims for the keyboard's player: once it has moved.
var _mouse_aims: bool = false
## The pause menu while it shows (null: closed).
var _pause_menu: PauseMenu = null

@onready var _session: UnifiedSession = Unified.session
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _effects: Effects = $Effects
@onready var _level: Node3D = $Level
@onready var _views: Node3D = $Views
@onready var _couch: Couch = $Couch
@onready var _hud: Hud = $Hud
@onready var _menus: CanvasLayer = $Menus


func _ready() -> void:
	_session.level_root = _level
	_session.view_root = _views
	_session.level_changed.connect(_on_level_changed)
	Game.listen(self, _session.input_wanted, _set_aims)
	_session.sim_event.connect(_on_sim_event)
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
	if not _session.running and Game.flow == Game.Flow.MENU:
		Game.start_single()  # the scene run on its own (the editor's Run Current Scene)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_aims = true


func _unhandled_input(event: InputEvent) -> void:
	if not _session.game_input:
		return  # an overlay holds the game's input: its keys aren't the game's
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		open_pause_menu()


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
## left where it was), none for the others, and none while game input is off.
func _set_aims() -> void:
	for local: int in _session.local_indices:
		var device: int = _session.get_local_device(local)
		var keyboard: bool = (device == UnifiedSession.DEVICE_KEYBOARD
			or device == UnifiedSession.DEVICE_ANY and Prompts.last_kind == Bindings.Kind.KEYBOARD)
		var aims: bool = keyboard and _mouse_aims and _session.game_input
		Unified.local_input(local).aim = _cursor_aim(local) if aims else Vector2.ZERO


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


## The floor is on screen: the camera frames its hero spawns until a local hero is there.
func _on_level_changed(_level_id: int) -> void:
	var sum := Vector3.ZERO
	var count: int = 0
	for marker: Node in Unified.level_markers(_level):
		if marker is HeroSpawn:
			sum += (marker as HeroSpawn).global_position
			count += 1
	if count > 0:
		_camera_rig.fallback = sum / count


## The effects of the sim's events, on their first showing (EMITTED), and what waits until it is certain (CONFIRMED:
## _on_sim_event_confirmed).
func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	if state == UnifiedSession.EVENT_CONFIRMED:
		_on_sim_event_confirmed(event)
	if state != UnifiedSession.EVENT_EMITTED:
		return
	if event is EventMinionHit:
		_effects.sparks((event as EventMinionHit).position + Vector3(0, HIT_HEIGHT, 0))
	elif event is EventBoltBurst:
		var bolt := event as EventBoltBurst
		if bolt.bone:
			_effects.sparks(bolt.position)  # a skeleton Mage's: bone splinters, not the hero's violet burst
		else:
			_effects.burst(bolt.position)
	elif event is EventCrossbowShot:
		var shot := event as EventCrossbowShot
		var shooter := _session.get_player_view(EnumView.HERO, shot.player) as HeroView
		_effects.tracer(shooter.weapon_position() if shooter != null else shot.from, shot.to)
	elif event is EventPropImpact:
		var impact := event as EventPropImpact
		if impact.speed >= DUST_SPEED:
			_effects.dust(impact.position)
	elif event is EventHeroHurt:
		if _session.get_local_index((event as EventHeroHurt).player) >= 0:
			_camera_rig.shake(HURT_SHAKE * Settings.screen_shake)
	# the abilities, and going down
	elif event is EventBlocked:
		_effects.sparks((event as EventBlocked).position)
		Sfx.play(&"block")
	elif event is EventFireballBurst:
		_effects.fireball((event as EventFireballBurst).position)
		Sfx.play(&"fireball")
		_camera_rig.shake(FIREBALL_SHAKE * Settings.screen_shake)
	elif event is EventHeroDowned:
		Sfx.play(&"downed")
	# Elites
	elif event is EventEliteHit:
		_effects.sparks((event as EventEliteHit).position + Vector3(0, ELITE_HIT_HEIGHT, 0))
	elif event is EventGuardBroken:
		var broken := event as EventGuardBroken
		_effects.sparks(broken.position + Vector3(0, ELITE_HIT_HEIGHT, 0))
		_effects.dust(broken.position)
	# Loot
	elif event is EventLootCollected:
		_effects.glint((event as EventLootCollected).position + Vector3(0, GLINT_HEIGHT, 0))


## What must not be taken back once shown, on its CONFIRMED showing: a revive's chime and its toast, and the wipe's
## banner (a revive or a wipe a rollback undid would have rung or hung for nothing).
func _on_sim_event_confirmed(event: UnifiedEvent) -> void:
	if event is EventHeroRevived:
		var revived := event as EventHeroRevived
		Sfx.play(&"revived")
		Game.toast("%s revived %s" % [_session.get_player_name(revived.by), _session.get_player_name(revived.player)])
	elif event is EventPartyWiped:
		_hud.show_wipe()
