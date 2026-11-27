class_name Sounds
extends Node
## Every sound of the world in play (a node of the play scene): it hears the session's sim events itself and plays
## them through Sfx (the fights, the mechanisms, the boss), the run's news through Music (its stingers, and the context
## its track and bed follow), and the heroes' footsteps from their views' data. Nothing else plays a world sound.
##
## Which state of an event a sound waits for is the event-state rule, the same for the effects:
## - an instant sound (no longer than Sfx.LINGER_S) plays on EMITTED, as soon as the event is predicted, and is never
##   undone: a hit heard a few ticks early is right far more often than not, and too short to take back;
## - a lingering sound (a gate's creak, a fireball's blast, the King's death knell) plays on EMITTED too, with the
##   event's id: a rollback that cancels the event (CANCELLED) fades it out in Sfx.FADE_S, its CONFIRMED lets it go;
## - news (the stingers, the music's changes, a revive's chime, a surge's toll) waits for CONFIRMED: it must not ring for
##   something a rollback takes back;
## - what lasts (the footsteps) is a function of view data, never of events, so a rollback or a replay seek never leaves
##   it wrong.
## A replay delivers each event EMITTED and CONFIRMED together, so each sound plays once there too.
##
## The footsteps follow each hero's gait as HeroView shows it: steps while it walks or runs and does nothing else, one
## every STEP_WALK_S or STEP_RUN_S of the shown time, at the hero's own phase (HeroView.PHASE_PER_KEY), so the party
## doesn't step in lockstep and a pause holds them. The music ducks while a menu (`menus`' child) or the boon choice
## (`hud`'s panels) is open over play.

## Seconds of shown time between a walking hero's steps, and a running one's.
const STEP_WALK_S: float = 0.5
const STEP_RUN_S: float = 0.33
## The footstep sounds, taken in turn.
const STEPS: Array[StringName] = [&"step_0", &"step_1", &"step_2", &"step_3"]

## The play scene's menus layer: a menu open in it ducks the music.
@export var menus: Node
## The HUD: its boon panels open duck the music.
@export var hud: Hud

## The session (Unified.session).
var _session: UnifiedSession
## The step each walking hero took last, by its player's key (absent: standing, or doing something else).
var _steps: Dictionary[int, int] = {}


func _ready() -> void:
	_session = Unified.session
	Game.listen(self, _session.sim_event, _on_sim_event)
	Game.listen(self, _session.level_changed, _on_level_changed)
	if menus != null:
		menus.child_entered_tree.connect(func(_menu: Node) -> void: _update_menu_open.call_deferred())
		menus.child_exiting_tree.connect(func(_menu: Node) -> void: _update_menu_open.call_deferred())
	if hud != null:
		hud.boon_panels().visibility_changed.connect(_update_menu_open)


func _exit_tree() -> void:
	Music.set_menu_open(false)
	Music.set_context(Music.TITLE)


func _process(_delta: float) -> void:
	_play_footsteps()


## Plays what event `event` sounds like in state `state` (the event-state rule, the header). `id` is the event's id,
## given apart so the audio checks can feed made-up events (a script-made event's own id is always 0).
func hear(event: UnifiedEvent, state: UnifiedSession.EventState, id: int) -> void:
	match state:
		UnifiedSession.EVENT_EMITTED:
			_on_emitted(event, id)
		UnifiedSession.EVENT_CONFIRMED:
			Sfx.forget(id)
			_on_confirmed(event)
		UnifiedSession.EVENT_CANCELLED:
			Sfx.cancel(id)


func _on_sim_event(event: UnifiedEvent, state: UnifiedSession.EventState) -> void:
	hear(event, state, event.id)


## The sounds of the event's first showing: everything but the news.
func _on_emitted(event: UnifiedEvent, id: int) -> void:
	# The fights
	if event is EventMinionHit:
		_play(&"hit", (event as EventMinionHit).position, Sfx.Priority.CROWD, id)
	elif event is EventMinionDied:
		_play(&"kill", (event as EventMinionDied).position, Sfx.Priority.CROWD, id)
	elif event is EventHeroAttacked:
		var attack := event as EventHeroAttacked
		_play_at_hero(_attack_sound(attack.class), attack.player, Sfx.Priority.ACTION, id)
	elif event is EventAbility:
		var ability := event as EventAbility
		_play_at_hero(&"cast" if ability.class == EnumClass.MAGE else &"cloth", ability.player, Sfx.Priority.ACTION, id)
	elif event is EventHeroHurt:
		_play(&"hurt", (event as EventHeroHurt).position, Sfx.Priority.ACTION, id)
	elif event is EventBlocked:
		_play(&"block", (event as EventBlocked).position, Sfx.Priority.ACTION, id)
	elif event is EventFireballBurst:
		_play(&"fireball", (event as EventFireballBurst).position, Sfx.Priority.ACTION, id)
	elif event is EventHeroDowned:
		_play(&"downed", (event as EventHeroDowned).position, Sfx.Priority.CRITICAL, id)
	elif event is EventHeaveLanded:
		_play(&"landing", (event as EventHeaveLanded).position, Sfx.Priority.ACTION, id)
	# Elites
	elif event is EventEliteHit:
		_play(&"hit", (event as EventEliteHit).position, Sfx.Priority.ACTION, id)
	elif event is EventGuardBroken:
		_play(&"guard_broken", (event as EventGuardBroken).position, Sfx.Priority.ACTION, id)
	elif event is EventEliteDied:
		_play(&"elite_death", (event as EventEliteDied).position, Sfx.Priority.ACTION, id)
	elif event is EventEliteCast:
		_play(&"cast", (event as EventEliteCast).position, Sfx.Priority.ACTION, id)
	# Mechanisms
	elif event is EventPlate:
		var plate := event as EventPlate
		if plate.pressed:
			_play(&"plate", plate.position, Sfx.Priority.ACTION, id)
	elif event is EventGate:
		var gate := event as EventGate
		_play(&"gate_open" if gate.open else &"gate_shut", gate.position, Sfx.Priority.ACTION, id)
	elif event is EventBarricadeBroken:
		_play(&"barricade", (event as EventBarricadeBroken).position, Sfx.Priority.ACTION, id)
	elif event is EventTrapHit:
		_play(&"trap", (event as EventTrapHit).position, Sfx.Priority.ACTION, id)
	# The hoard put down, the lift's deck stopping at the shaft's bottom, a shrine turned
	elif event is EventHoardDropped:
		_play_at_hero(&"thud", (event as EventHoardDropped).player, Sfx.Priority.ACTION, id)
	elif event is EventLift:
		if (event as EventLift).phase == EnumLiftPhase.CHOOSING:
			Sfx.play_world(&"thud", Sfx.Priority.ACTION, id if Sfx.lingers(&"thud") else 0)
	elif event is EventShrine:
		_play_at_hero(&"plate", (event as EventShrine).player, Sfx.Priority.ACTION, id)
	# Braziers and the boss
	elif event is EventBrazier:
		var brazier := event as EventBrazier
		_play(&"kindle" if brazier.lit else &"brazier_out", brazier.position, Sfx.Priority.ACTION, id)
	elif event is EventBossStage:
		Sfx.play_world(&"roar", Sfx.Priority.CRITICAL, id if Sfx.lingers(&"roar") else 0)
	elif event is EventBossSlam:
		_play(&"slam", (event as EventBossSlam).position, Sfx.Priority.CRITICAL, id)
	elif event is EventBossWard:
		if not (event as EventBossWard).up:
			Sfx.play_world(&"ward_broken", Sfx.Priority.CRITICAL, id if Sfx.lingers(&"ward_broken") else 0)
	elif event is EventBossDefeated:
		_play(&"boss_death", (event as EventBossDefeated).position, Sfx.Priority.CRITICAL, id)


## The news, once certain: the stingers and the music's context, a revive's chime and a surge's toll.
func _on_confirmed(event: UnifiedEvent) -> void:
	if event is EventHeroRevived:
		Sfx.play_at(&"revived", (event as EventHeroRevived).position, Sfx.Priority.ACTION)
	elif event is EventSurge:
		Sfx.play_world(&"toll", Sfx.Priority.ACTION)
	elif event is EventRunBegan:
		Music.sting(&"run_began")
	elif event is EventLifeLost:
		if (event as EventLifeLost).lives > 0:
			Music.sting(&"life_lost")  # the last life's loss is the run's end, which says so itself
	elif event is EventDescended:
		Music.sting(&"descent")
	elif event is EventBossStage:
		Music.sting(&"boss_stage")
		Music.set_context(Music.KING)
	elif event is EventBossDefeated:
		Music.sting(&"victory")
		Music.set_context(Music.FLOOR)
	elif event is EventRunEnded:
		if not (event as EventRunEnded).won:
			Music.sting(&"run_lost")  # a won run's victory rang as the King fell
		Music.set_context(Music.RESULTS)


## The verified level is on screen: the music follows it (the King's fight begins on its stage's confirmation).
func _on_level_changed(level_id: int) -> void:
	match level_id:
		EnumLevel.HUB:
			Music.set_context(Music.HUB)
		EnumLevel.ARENA:
			Music.set_context(Music.PIT)
		_:
			Music.set_context(Music.FLOOR)


## Plays `sound` at `position`, with event `id` when it lingers, so a cancel can fade it.
func _play(sound: StringName, position: Vector3, priority: Sfx.Priority, id: int) -> void:
	Sfx.play_at(sound, position, priority, id if Sfx.lingers(sound) else 0)


## Plays `sound` where player `player`'s hero is shown; with no hero view, with no place.
func _play_at_hero(sound: StringName, player: int, priority: Sfx.Priority, id: int) -> void:
	var hero := _session.get_player_view(EnumView.HERO, player) as Node3D
	if hero != null:
		_play(sound, hero.global_position, priority, id)
	else:
		Sfx.play_world(sound, priority, id if Sfx.lingers(sound) else 0)


## The sound of a class's attack: the Knight's sword, the Barbarian's axe, the Rogue's crossbow, the Mage's bolt.
func _attack_sound(hero_class: int) -> StringName:
	match hero_class:
		EnumClass.BARBARIAN:
			return &"axe"
		EnumClass.ROGUE:
			return &"shot"
		EnumClass.MAGE:
			return &"cast"
	return &"swing"


## A step for each hero whose gait has come round to its next one (the header).
func _play_footsteps() -> void:
	var now_s: float = _session.shown_time / Unified.tick_hz
	for player: int in _session.players:
		var hero := _session.get_player_view(EnumView.HERO, player) as HeroView
		if hero == null or hero.data == null:
			_steps.erase(player)
			continue
		var data: ViewHero = hero.data
		if data.action != EnumAction.NONE or data.ragdoll or data.velocity.length() < HeroView.WALK_FROM:
			_steps.erase(player)
			continue
		var period: float = STEP_RUN_S if data.velocity.y >= HeroView.RUN_FROM else STEP_WALK_S
		var step: int = floori((now_s + float(player) * HeroView.PHASE_PER_KEY) / period)
		if _steps.get(player, step) != step:
			Sfx.play_at(STEPS[posmod(step, STEPS.size())], hero.global_position, Sfx.Priority.CROWD)
		_steps[player] = step


## Whether a menu or the boon choice is open over play, for the music's duck.
func _update_menu_open() -> void:
	var open: bool = menus != null and menus.get_child_count() > 0
	if hud != null:
		open = open or hud.boon_panels().visible
	Music.set_menu_open(open)
