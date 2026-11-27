extends Node
## The game's music (the `Music` autoload): a bed of room tone under everything, a track for where the game is, and
## stingers for the run's news, all on the Music bus; and the crypt's distant noises on the World bus.
##
## Where the game is, its context (set_context: the title, the hub, a floor, the King's fight, the Pit, the results), picks
## its track from `tracks`, crossfading over CROSSFADE_S. The game ships no tracks yet, so every context's is missing,
## and a missing track is silence over the bed: a track added to music.tscn (an Ogg imported to loop) plays from then on,
## and nothing else changes. The play scene's Sounds sets the context from the verified level and the boss's confirmed
## events, and plays the stingers (Kenney's Music Jingles) on confirmed news; nothing here hears the sim.
##
## The bed is generated, not a file: white noise through two low-pass stages into an AudioStreamGenerator, dark and close
## in the crypt, higher and fainter (airy) in the hub and on the title, its level breathing slowly, easing between the
## two as the context changes. In the crypt a creak or a far-off clank (`ambience`) sounds every AMBIENCE_MIN_S to
## AMBIENCE_MAX_S, at a random pitch below its own, from a view-only RNG.
##
## Ducking: the Music bus's Duck effect (bus_layout.tres) drops DUCK_CRITICAL_DB for DUCK_CRITICAL_S when a critical
## world sound starts (Sfx.world_played), and DUCK_MENU_DB while a menu or a boon choice is open over play
## (set_menu_open), so what matters is heard over the music. The settings' music volume is the bus's own level.

## A stinger started (tools count them).
signal stung(stinger: StringName)

## The contexts: the title's menus, the graveyard hub, a crypt floor, the Bone King's fight, the Pit, a run's results.
const TITLE: StringName = &"title"
const HUB: StringName = &"hub"
const FLOOR: StringName = &"floor"
const KING: StringName = &"king"
const PIT: StringName = &"pit"
const RESULTS: StringName = &"results"
## The contexts under the crypt's dark bed (the rest have the hub's airy one), and those its noises sound in.
const DARK: Array[StringName] = [FLOOR, KING, PIT, RESULTS]
const NOISY: Array[StringName] = [FLOOR, KING, PIT]
## How long a context's change takes: the tracks' crossfade, the bed's ease (seconds).
const CROSSFADE_S: float = 1.5
## The duck under a critical world sound (dB, seconds), and while a menu is open (dB); how fast it moves (dB a second).
const DUCK_CRITICAL_DB: float = -6.0
const DUCK_CRITICAL_S: float = 1.2
const DUCK_MENU_DB: float = -8.0
const DUCK_RATE_DB: float = 30.0
## The bed's sample rate (it holds nothing high) and how far ahead it is generated (seconds).
const TONE_RATE: float = 11025.0
const TONE_BUFFER_S: float = 0.25
## The crypt's bed: noise low-passed at CRYPT_TONE_HZ, at CRYPT_TONE_DB; the hub's, airier and fainter.
const CRYPT_TONE_HZ: float = 150.0
const CRYPT_TONE_DB: float = -14.0
const HUB_TONE_HZ: float = 1100.0
const HUB_TONE_DB: float = -26.0
## The bed's level swells and ebbs by BREATH_DEPTH (a fraction) over BREATH_S seconds.
const BREATH_S: float = 11.0
const BREATH_DEPTH: float = 0.3
## The crypt's noises: one every AMBIENCE_MIN_S to AMBIENCE_MAX_S seconds, at AMBIENCE_DB, its pitch scaled down to as
## low as AMBIENCE_PITCH_MIN (far off).
const AMBIENCE_MIN_S: float = 8.0
const AMBIENCE_MAX_S: float = 20.0
const AMBIENCE_DB: float = -16.0
const AMBIENCE_PITCH_MIN: float = 0.75
## The level a silent track's player sits at while it fades (dB): linear_to_db of nothing is minus infinity.
const SILENT_DB: float = -80.0

## Each context's track (none yet: a missing one is silence over the bed).
@export var tracks: Dictionary[StringName, AudioStream] = {}
## The run's news: `run_began`, `boss_stage`, `victory`, `run_lost`, `life_lost`, `descent`.
@export var stingers: Dictionary[StringName, AudioStream] = {}
## The crypt's distant noises, one picked at random each time.
@export var ambience: Array[AudioStream] = []

## The context the music follows (set_context).
var context: StringName = TITLE

## The two track players the crossfade swaps between, and how loud each is now (0 to 1).
var _tracks: Array[AudioStreamPlayer] = []
var _weights: PackedFloat32Array = [0.0, 0.0]
## The track player of the current context.
var _current: int = 0
var _stinger: AudioStreamPlayer
var _tone: AudioStreamPlayer
var _tone_playback: AudioStreamGeneratorPlayback
## The bed's two filter stages, its cutoff and linear level now (easing toward the context's), and its breath's phase.
var _low_1: float = 0.0
var _low_2: float = 0.0
var _cutoff_hz: float = HUB_TONE_HZ
var _tone_level: float = db_to_linear(HUB_TONE_DB)
var _breath: float = 0.0
var _ambience: AudioStreamPlayer
var _ambience_timer: Timer
## The Music bus's Duck effect (null without one: no ducking), how long a critical sound's duck lasts yet, and whether a
## menu is open over play.
var _duck: AudioEffectAmplify = null
var _duck_left_s: float = 0.0
var _menu_open: bool = false
## The bed's noise and the ambience's picks: view-only randomness, never the sim's.
var _rng := RandomNumberGenerator.new()
## The app is quitting: nothing plays any more (close).
var _closed: bool = false


func _ready() -> void:
	_rng.randomize()
	for i: int in 2:
		var player := AudioStreamPlayer.new()
		player.bus = &"Music"
		player.volume_db = SILENT_DB
		add_child(player)
		_tracks.append(player)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = &"Music"
	add_child(_stinger)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = TONE_RATE
	generator.buffer_length = TONE_BUFFER_S
	_tone = AudioStreamPlayer.new()
	_tone.bus = &"Music"
	_tone.stream = generator
	add_child(_tone)
	_tone.play()
	_tone_playback = _tone.get_stream_playback()
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"World"
	_ambience.volume_db = AMBIENCE_DB
	add_child(_ambience)
	_ambience_timer = Timer.new()
	_ambience_timer.one_shot = true
	_ambience_timer.timeout.connect(_on_ambience_timer)
	add_child(_ambience_timer)
	_ambience_timer.start(_rng.randf_range(AMBIENCE_MIN_S, AMBIENCE_MAX_S))
	var bus: int = AudioServer.get_bus_index(&"Music")
	if bus >= 0 and AudioServer.get_bus_effect_count(bus) > 0:
		_duck = AudioServer.get_bus_effect(bus, 0) as AudioEffectAmplify
	Sfx.world_played.connect(_on_world_played)


func _process(delta: float) -> void:
	for i: int in 2:
		var target: float = 1.0 if i == _current and _tracks[i].playing else 0.0
		_weights[i] = move_toward(_weights[i], target, delta / CROSSFADE_S)
		_tracks[i].volume_db = linear_to_db(_weights[i]) if _weights[i] > 0.0 else SILENT_DB
		if _weights[i] == 0.0 and i != _current and _tracks[i].playing:
			_tracks[i].stop()
	_duck_left_s = maxf(_duck_left_s - delta, 0.0)
	if _duck != null:
		var duck_db: float = minf(DUCK_MENU_DB if _menu_open else 0.0, DUCK_CRITICAL_DB if _duck_left_s > 0.0 else 0.0)
		_duck.volume_db = move_toward(_duck.volume_db, duck_db, DUCK_RATE_DB * delta)
	_fill_tone(delta)


## Follows the game to context `next` (TITLE, HUB, ...): its track crossfades in over CROSSFADE_S (none: the last fades
## to silence over the bed), and the bed eases to the context's.
func set_context(next: StringName) -> void:
	if _closed or next == context:
		return
	context = next
	var track: AudioStream = tracks.get(next)
	if track != null and _tracks[_current].stream == track and _tracks[_current].playing:
		return  # the same track carries on
	_current = 1 - _current
	_tracks[_current].stop()
	_tracks[_current].stream = track
	_weights[_current] = 0.0
	if track != null:
		_tracks[_current].play()


## The track playing for the context now (null: none, the bed alone).
func track() -> AudioStream:
	var player: AudioStreamPlayer = _tracks[_current]
	return player.stream if player.playing else null


## Plays stinger `stinger` (one of `stingers`' names) over the track, cutting short the one before.
func sting(stinger: StringName) -> void:
	if _closed:
		return
	var stream: AudioStream = stingers.get(stinger)
	if stream == null:
		push_error("Music: no stinger %s" % stinger)
		return
	_stinger.stream = stream
	_stinger.play()
	stung.emit(stinger)


## Whether a menu or a boon choice is open over play: the music ducks DUCK_MENU_DB while one is.
func set_menu_open(open: bool) -> void:
	_menu_open = open


## The app is quitting (Game.quit_app): nothing starts or is generated any more, and the bed's playback is let go, so
## the session's quit, which stops every player, sees each playback freed and none is held at exit.
func close() -> void:
	_closed = true
	set_process(false)
	_ambience_timer.stop()
	_tone_playback = null


## Tops the bed's buffer up: noise through the two low-pass stages at the cutoff and level now, both easing toward the
## context's bed, the level breathing.
func _fill_tone(delta: float) -> void:
	if not _tone.playing:
		return
	var dark: bool = context in DARK
	var eased: float = minf(delta / CROSSFADE_S, 1.0)
	_cutoff_hz = lerpf(_cutoff_hz, CRYPT_TONE_HZ if dark else HUB_TONE_HZ, eased)
	_tone_level = lerpf(_tone_level, db_to_linear(CRYPT_TONE_DB if dark else HUB_TONE_DB), eased)
	_breath = fmod(_breath + delta / BREATH_S, 1.0)
	var frames: int = _tone_playback.get_frames_available()
	if frames <= 0:
		return
	var a: float = 1.0 - exp(-TAU * _cutoff_hz / TONE_RATE)
	# A one-pole low-pass keeps a/(2 - a) of white noise's power: this brings it back up, so the level is the bed's own.
	var gain: float = _tone_level * sqrt((2.0 - a) / a) * (1.0 + BREATH_DEPTH * sin(TAU * _breath))
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	for i: int in frames:
		_low_1 += a * (_rng.randf_range(-1.0, 1.0) - _low_1)
		_low_2 += a * (_low_1 - _low_2)
		var sample: float = _low_2 * gain
		buffer[i] = Vector2(sample, sample)
	_tone_playback.push_buffer(buffer)


func _on_world_played(_sound: StringName, priority: Sfx.Priority) -> void:
	if priority == Sfx.Priority.CRITICAL:
		_duck_left_s = DUCK_CRITICAL_S


## One of the crypt's noises, while the game is in it, and the next one's wait.
func _on_ambience_timer() -> void:
	if context in NOISY and not ambience.is_empty():
		_ambience.stream = ambience[_rng.randi_range(0, ambience.size() - 1)]
		_ambience.pitch_scale = _rng.randf_range(AMBIENCE_PITCH_MIN, 1.0)
		_ambience.play()
	_ambience_timer.start(_rng.randf_range(AMBIENCE_MIN_S, AMBIENCE_MAX_S))
