extends Node
## The game's sounds (the `Sfx` autoload), from two pools of voices so a sound never cuts off one it shouldn't.
##
## The interface's (play): Kenney's Interface Sounds and a few of RPG Audio's (a pickup's chime once confirmed, a
## boon's, the lift's creak) on the Interface bus, from VOICES voices, the one that started longest ago giving way.
## Which control makes which sound is Game's rule (every button sounds when pressed, the focus moving between controls
## sounds), so no menu script plays a click by hand.
##
## The world's (play_at, play_world): the fights, the mechanisms, the boss and the heroes' footsteps (Impact Sounds and
## RPG Audio), which the play scene's Sounds plays on the sim's events, on the World bus from WORLD_VOICES positional
## voices that the camera rig's listener hears (Godot's inverse-distance falloff, its panning softened). The pool is
## capped by priority (Priority): when every voice is busy, a sound takes the oldest voice of the lowest priority at or
## below its own, else it is dropped, so a crowd's hits never silence the boss. One sound holds at most SAME_SOUND_MAX
## voices and never starts twice within SAME_SOUND_GAP_USEC, so 200 hits in a frame are one hit, not a wall of noise.
## Each world sound's pitch strays by up to PITCH_SPREAD (a view-only RNG), so repeats don't sound sampled.
##
## A sound that lingers (longer than LINGER_S) is started with its event's id, so a rollback that cancels the event
## fades it out (cancel) and its confirmation lets it go (forget): the event-state rule, Sounds' header.
##
## The sounds are `sounds`, set in sfx.tscn rather than loaded by path, so the scene's dependencies say which files of
## the packs the game uses (the art checks hold every vendored file to that); each one's pitch and level are data there
## too (pitches, volumes_db, rising).

## A sound started, the interface's or the world's (tools count them: a dialog plays one error, not two).
signal played(sound: StringName)
## A world sound started at `priority`: Music ducks under a critical one.
signal world_played(sound: StringName, priority: Priority)

## How much a world sound matters when voices run short: a crowd's hits, kills and steps; a hero's actions and the
## mechanisms; what nobody may miss (a hero down, the boss's roar, slam and ward, its death).
enum Priority { CROWD, ACTION, CRITICAL }

## The interface's voices.
const VOICES: int = 4
## The world's voices.
const WORLD_VOICES: int = 16
## The most voices one world sound holds at once.
const SAME_SOUND_MAX: int = 3
## A world sound never starts again this soon after it last started (microseconds).
const SAME_SOUND_GAP_USEC: int = 50_000
## How far a world sound's pitch strays either way, as a fraction.
const PITCH_SPREAD: float = 0.06
## A sound longer than this (seconds, at its pitch) lingers: its event's id lets a rollback fade it out.
const LINGER_S: float = 0.5
## How long a cancelled sound takes to fade out (seconds), and the level the fade ends at before the voice stops (dB).
const FADE_S: float = 0.08
const FADE_DB: float = -60.0
## The world's falloff: full level within UNIT_SIZE metres of the listener, nothing past MAX_DISTANCE; PANNING of
## Godot's full left-right spread.
const UNIT_SIZE: float = 12.0
const MAX_DISTANCE: float = 45.0
const PANNING: float = 0.6
## A rising sound repeated within this (microseconds) plays a semitone higher than the last, up to RISE_STEPS_MAX.
const RISE_WINDOW_USEC: int = 400_000
const RISE_STEPS_MAX: int = 7


## A world voice and what it plays.
class Voice:
	var player: AudioStreamPlayer3D
	## The sound it plays (&"": none yet).
	var sound: StringName = &""
	var priority: Priority = Priority.CROWD
	## When it started (Time.get_ticks_usec).
	var started: int = 0
	## The event it plays for (0: none, or let go): cancel(id) fades it out.
	var id: int = 0
	## Its fade out, while a cancel fades it (null: none).
	var fade: Tween = null

	## Whether it plays a sound that is not fading out.
	func busy() -> bool:
		return player.playing and fade == null


## Every sound by name. The interface's: `press`, `select`, `confirm`, `error`, `joined`, `left`, `coin`, `boon`,
## `creak` (the lift's). The world's: `hit`, `kill`, `swing`, `axe`, `shot`, `cast`, `cloth`, `hurt`, `block`,
## `fireball`, `downed`, `revived`, `landing`, `guard_broken`, `elite_death`, `plate`, `gate_open`, `gate_shut`,
## `barricade`, `trap`, `thud`, `kindle`, `brazier_out`, `roar`, `slam`, `ward_broken`, `boss_death`, `toll`, and the
## footsteps `step_0` to `step_3`.
@export var sounds: Dictionary[StringName, AudioStream] = {}
## A sound's pitch before its spread (1 when absent): the landing's low thud, the bell slowed for the King's death and
## the surge's toll.
@export var pitches: Dictionary[StringName, float] = {}
## A sound's level in dB (0 when absent): the footsteps under everything.
@export var volumes_db: Dictionary[StringName, float] = {}
## The sounds whose quick repeats climb (RISE_WINDOW_USEC): a run of coins chimes up a scale.
@export var rising: Array[StringName] = []

var _voices: Array[AudioStreamPlayer] = []
## When each interface voice last started a sound (Time.get_ticks_usec): the oldest gives way when every voice is busy.
var _started: PackedInt64Array = []
var _world: Array[Voice] = []
## When each sound last started (Time.get_ticks_usec): SAME_SOUND_GAP_USEC and the rising sounds' climb.
var _last_started: Dictionary[StringName, int] = {}
## How many semitones each rising sound has climbed.
var _rise: Dictionary[StringName, int] = {}
## The pitch spread's: view-only randomness, never the sim's.
var _rng := RandomNumberGenerator.new()
## The app is quitting: nothing plays any more (close).
var _closed: bool = false


func _ready() -> void:
	_rng.randomize()
	for i: int in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"Interface"
		add_child(voice)
		_voices.append(voice)
	_started.resize(VOICES)
	for i: int in WORLD_VOICES:
		var voice := Voice.new()
		voice.player = AudioStreamPlayer3D.new()
		voice.player.bus = &"World"
		voice.player.unit_size = UNIT_SIZE
		voice.player.max_distance = MAX_DISTANCE
		add_child(voice.player)
		_world.append(voice)


## Plays interface sound `sound` (one of `sounds`' names) on an idle voice, else on the one that started longest ago;
## nothing once the app is quitting.
func play(sound: StringName) -> void:
	if _closed:
		return
	var stream: AudioStream = _stream(sound)
	if stream == null:
		return
	var index: int = 0
	for i: int in VOICES:
		if not _voices[i].playing:
			index = i
			break
		if _started[i] < _started[index]:
			index = i
	var now: int = Time.get_ticks_usec()
	_started[index] = now
	_voices[index].stream = stream
	_voices[index].volume_db = volumes_db.get(sound, 0.0)
	_voices[index].pitch_scale = _rising_pitch(sound, now) * pitches.get(sound, 1.0)
	_last_started[sound] = now
	_voices[index].play()
	played.emit(sound)


## Plays world sound `sound` at `position` (the world's coordinates) as `priority`, under the pool's cap (the header).
## `id`: the event it is for when the sound lingers (Sounds passes it then), so cancel(id) can fade it out; 0: none.
func play_at(sound: StringName, position: Vector3, priority: Priority, id: int = 0) -> void:
	_play_world(sound, position, true, priority, id)


## Plays world sound `sound` with no place (a surge's toll, the lift's stop): on the World bus under the same cap, heard
## alike wherever the camera is. `id` as play_at's.
func play_world(sound: StringName, priority: Priority, id: int = 0) -> void:
	_play_world(sound, Vector3.ZERO, false, priority, id)


## Fades out over FADE_S the sounds started for event `id` (its CANCELLED: a rollback took it back); 0 does nothing.
func cancel(id: int) -> void:
	if id == 0:
		return
	for voice: Voice in _world:
		if voice.id != id:
			continue
		voice.id = 0
		if not voice.busy():
			continue
		voice.fade = create_tween()
		voice.fade.tween_property(voice.player, ^"volume_db", FADE_DB, FADE_S)
		voice.fade.tween_callback(_stop.bind(voice))


## Lets go of event `id` (its CONFIRMED): its sounds play out, and nothing can cancel them any more.
func forget(id: int) -> void:
	if id == 0:
		return
	for voice: Voice in _world:
		if voice.id == id:
			voice.id = 0


## Whether `sound` lingers (longer than LINGER_S at its pitch), so its event's id goes with it (play_at's `id`).
func lingers(sound: StringName) -> bool:
	var stream: AudioStream = sounds.get(sound)
	return stream != null and stream.get_length() / pitches.get(sound, 1.0) > LINGER_S


## Each world voice as tools read it: `sound` (&"" before its first), `priority`, `id`, `playing`, and `fading` (a
## cancel fades it out).
func world_voices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for voice: Voice in _world:
		out.append({"sound": voice.sound, "priority": voice.priority, "id": voice.id, "playing": voice.player.playing,
			"fading": voice.fade != null})
	return out


## The app is quitting (Game.quit_app): later plays are ignored, so no sound starts while the session stops every
## playback before the quit (a playback started then would be held at exit, a leak).
func close() -> void:
	_closed = true


func _play_world(sound: StringName, position: Vector3, placed: bool, priority: Priority, id: int) -> void:
	if _closed:
		return
	var stream: AudioStream = _stream(sound)
	if stream == null:
		return
	var now: int = Time.get_ticks_usec()
	if _last_started.has(sound) and now - _last_started[sound] < SAME_SOUND_GAP_USEC:
		return
	var same: int = 0
	for voice: Voice in _world:
		if voice.busy() and voice.sound == sound:
			same += 1
	if same >= SAME_SOUND_MAX:
		return
	var voice: Voice = _free_voice(priority)
	if voice == null:
		return
	if voice.fade != null:
		voice.fade.kill()
		voice.fade = null
	voice.sound = sound
	voice.priority = priority
	voice.started = now
	voice.id = id
	var player: AudioStreamPlayer3D = voice.player
	player.stream = stream
	player.position = position
	player.attenuation_model = (AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE if placed
		else AudioStreamPlayer3D.ATTENUATION_DISABLED)
	player.panning_strength = PANNING if placed else 0.0
	player.volume_db = volumes_db.get(sound, 0.0)
	player.pitch_scale = pitches.get(sound, 1.0) * (1.0 + _rng.randf_range(-PITCH_SPREAD, PITCH_SPREAD))
	_last_started[sound] = now
	player.play()
	played.emit(sound)
	world_played.emit(sound, priority)


## The voice a sound of `priority` plays on: an idle one (or one fading out), else the oldest of the lowest priority at
## or below `priority`; null when every voice plays something that matters more.
func _free_voice(priority: Priority) -> Voice:
	var taken: Voice = null
	for voice: Voice in _world:
		if not voice.busy():
			return voice
		if voice.priority > priority:
			continue
		if (taken == null or voice.priority < taken.priority
				or voice.priority == taken.priority and voice.started < taken.started):
			taken = voice
	return taken


## The pitch a rising sound climbs to, played now (1 for any other): a semitone over its last when that was within
## RISE_WINDOW_USEC, else back to its own.
func _rising_pitch(sound: StringName, now: int) -> float:
	if sound not in rising:
		return 1.0
	var recent: bool = _last_started.has(sound) and now - _last_started[sound] < RISE_WINDOW_USEC
	var climbed: int = _rise.get(sound, 0)
	var steps: int = mini(climbed + 1, RISE_STEPS_MAX) if recent else 0
	_rise[sound] = steps
	return pow(2.0, steps / 12.0)


## `sound`'s stream; null, and an error, when there is no such sound.
func _stream(sound: StringName) -> AudioStream:
	var stream: AudioStream = sounds.get(sound)
	if stream == null:
		push_error("Sfx: no sound %s" % sound)
	return stream


## The end of a cancel's fade: the voice stops and is free.
func _stop(voice: Voice) -> void:
	voice.player.stop()
	voice.fade = null
