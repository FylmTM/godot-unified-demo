class_name AudioChecks
extends RefCounted
## The game's audio, checked headless: nobody listens, so what plays is counted through Sfx.played and read from the
## voices' states (Sfx.world_voices). The godot suite's validate step runs it once the main scene has run
## (game/tools/validate.gd), with the autoloads up; it plays into a muted engine, and puts back what it changed.
##
## - The buses the code names exist and send to Master: Music (its Duck effect first), World, Interface; Master ends
##   in a hard limiter.
## - Sfx's cap, on a fresh Sfx with long silent test sounds (so nothing ends mid-check): 200 hits in a frame start at
##   most SAME_SOUND_MAX voices, and hits spaced past the gap hold no more than that either; with every voice busy with
##   the crowd a critical sound still plays; a crowd sound never steals a critical one, and an action sound takes the
##   crowd's voice among critical ones, not the oldest.
## - Sfx.cancel(id) fades a sound started with that id out within a tenth of a second, and leaves one without.
## - Sounds, fed made-up events: live (EMITTED, then CONFIRMED a moment later) and in a replay (both together) each
##   sound plays once; a cancelled lingering sound fades and an instant one is left; the news (a stinger, the music's
##   context) waits for CONFIRMED. Every sound and stinger it names exists.
## - Music: a context with a track plays it, and a missing track is silence.
##
## Each problem is reported through the validate run's log capture, named by the file it is in.

const SFX: String = "res://game/app/sfx.tscn"
const MUSIC: String = "res://game/app/music.tscn"
const SOUNDS: String = "res://game/play/sounds.gd"
const BUS_LAYOUT: String = "res://game/app/bus_layout.tres"
## The buses the code plays on, besides Master.
const BUSES: Array[StringName] = [&"Music", &"World", &"Interface"]
## The test sounds' length (seconds): longer than any check, so a voice only stops when the code stops it.
const TEST_SOUND_S: float = 5.0
## Sfx's priorities, as numbers (a tool script names no autoload's script).
const CROWD: int = 0
const ACTION: int = 1
const CRITICAL: int = 2
## How long a check waits for a cancel's fade to end (seconds): past Sfx.FADE_S.
const FADE_WAIT_S: float = 0.15
## How long a live event's CONFIRMED follows its EMITTED here (seconds): past Sfx's same-sound gap, as a round trip is.
const CONFIRM_DELAY_S: float = 0.1

## How many problems the checks found.
var problems: int = 0

var _tool: UnifiedTool
## The Sfx under test (a fresh one per check, or the autoload).
var _sfx: Node = null


## Checks run in `tool`'s tree, report to its log capture and wait on its frames.
func _init(tool: UnifiedTool) -> void:
	_tool = tool


## Runs every check.
func run() -> void:
	var listener_root := Node3D.new()
	var listener := AudioListener3D.new()
	listener_root.add_child(listener)
	_tool.root.add_child(listener_root)
	listener.make_current()
	_check_buses()
	await _check_cap()
	await _check_cancel()
	await _check_sounds()
	_check_music()
	listener_root.free()
	await _tool.seconds(FADE_WAIT_S)  # the mixer lets go of the freed players' playbacks, or they are held at exit


func _check_buses() -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	var count: int = AudioServer.get_bus_effect_count(master)
	if count == 0 or not AudioServer.get_bus_effect(master, count - 1) is AudioEffectHardLimiter:
		_problem("Master doesn't end in a hard limiter", BUS_LAYOUT)
	for bus: StringName in BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		if index < 0:
			_problem("no audio bus %s, which the code plays on" % bus, BUS_LAYOUT)
		elif AudioServer.get_bus_send(index) != &"Master":
			_problem("bus %s sends to %s, not Master" % [bus, AudioServer.get_bus_send(index)], BUS_LAYOUT)
	var music: int = AudioServer.get_bus_index(&"Music")
	if music >= 0 and (AudioServer.get_bus_effect_count(music) == 0
			or not AudioServer.get_bus_effect(music, 0) is AudioEffectAmplify):
		_problem("the Music bus has no Duck (an AudioEffectAmplify, its first effect)", BUS_LAYOUT)


func _check_cap() -> void:
	_fresh_sfx()
	for i: int in 200:
		_sfx.call(&"play_at", &"hit", Vector3.ZERO, CROWD)
	var hits: int = _busy(&"hit")
	_expect(hits >= 1 and hits <= 3, "200 hits in a frame start 1 to 3 voices (%d)" % hits)
	_fresh_sfx()
	for i: int in 6:
		_sfx.call(&"play_at", &"hit", Vector3.ZERO, CROWD)
		await _tool.seconds(0.06)
	hits = _busy(&"hit")
	_expect(hits == 3, "hits past the gap hold 3 voices, no more (%d)" % hits)
	_fresh_sfx()
	for i: int in 16:
		_sfx.call(&"play_at", StringName("crowd_%d" % i), Vector3.ZERO, CROWD)
	_sfx.call(&"play_at", &"roar", Vector3.ZERO, CRITICAL)
	_expect(_busy(&"roar") == 1 and _busy_at(CROWD) == 15, "with 16 crowd voices busy a roar still plays (%d roar, %d crowd)"
		% [_busy(&"roar"), _busy_at(CROWD)])
	_fresh_sfx()
	for i: int in 16:
		_sfx.call(&"play_at", StringName("critical_%d" % i), Vector3.ZERO, CRITICAL)
	_sfx.call(&"play_at", &"crowd_0", Vector3.ZERO, CROWD)
	_expect(_busy_at(CRITICAL) == 16 and _busy(&"crowd_0") == 0, "a crowd sound never steals a critical one (%d critical)"
		% _busy_at(CRITICAL))
	_fresh_sfx()
	for i: int in 15:
		_sfx.call(&"play_at", StringName("critical_%d" % i), Vector3.ZERO, CRITICAL)
	_sfx.call(&"play_at", &"crowd_0", Vector3.ZERO, CROWD)
	_sfx.call(&"play_at", &"action", Vector3.ZERO, ACTION)
	_expect(_busy(&"action") == 1 and _busy(&"crowd_0") == 0 and _busy_at(CRITICAL) == 15,
		"an action sound takes the crowd's voice, not the oldest critical one")
	_free_sfx()


func _check_cancel() -> void:
	_fresh_sfx()
	_sfx.call(&"play_at", &"long_a", Vector3.ZERO, ACTION, 42)
	_sfx.call(&"play_at", &"long_b", Vector3.ZERO, ACTION)
	_sfx.call(&"cancel", 42)
	_sfx.call(&"cancel", 0)
	_expect(_fading(&"long_a") and not _fading(&"long_b"), "cancel(42) fades its sound at once, and nothing else")
	await _tool.seconds(FADE_WAIT_S)
	_expect(_busy(&"long_a") == 0 and not _playing(&"long_a"), "a cancelled sound is silent after %.2f s" % FADE_WAIT_S)
	_expect(_busy(&"long_b") == 1, "a sound without an id plays on")
	_free_sfx()


## Sounds fed made-up events, playing into the Sfx and Music autoloads.
func _check_sounds() -> void:
	_sfx = _tool.root.get_node(^"Sfx")
	var music: Node = _tool.root.get_node(^"Music")
	var sounds: Node = (load(SOUNDS) as GDScript).new()
	_tool.root.add_child(sounds)
	var played: Array[StringName] = []
	var on_played: Callable = func(sound: StringName) -> void: played.append(sound)
	_sfx.connect(&"played", on_played)
	var stung: Array[StringName] = []
	var on_stung: Callable = func(stinger: StringName) -> void: stung.append(stinger)
	music.connect(&"stung", on_stung)
	var events: Array[UnifiedEvent] = [EventBlocked.new(), EventHeroDowned.new(), EventGate.new(), EventTrapHit.new(),
		EventBarricadeBroken.new(), EventBossSlam.new(), EventHeroRevived.new(), EventSurge.new()]
	var want: Array[StringName] = [&"block", &"downed", &"gate_shut", &"trap", &"barricade", &"slam", &"revived", &"toll"]
	_quiet()
	for i: int in events.size():
		sounds.call(&"hear", events[i], UnifiedSession.EVENT_EMITTED, 1000 + i)
	await _tool.seconds(CONFIRM_DELAY_S)
	for i: int in events.size():
		sounds.call(&"hear", events[i], UnifiedSession.EVENT_CONFIRMED, 1000 + i)
	_expect(played == want, "live (EMITTED, then CONFIRMED), each sound plays once: %s, want %s" % [played, want], SOUNDS)
	_expect(_voices().all(func(v: Dictionary) -> bool: return v["id"] == 0), "a confirmed event's sound is let go", SOUNDS)
	await _tool.seconds(CONFIRM_DELAY_S)
	_quiet()
	played.clear()
	for i: int in events.size():
		sounds.call(&"hear", events[i], UnifiedSession.EVENT_EMITTED, 1100 + i)
		sounds.call(&"hear", events[i], UnifiedSession.EVENT_CONFIRMED, 1100 + i)
	_expect(played == want, "in a replay (EMITTED and CONFIRMED together), each sound plays once: %s, want %s"
		% [played, want], SOUNDS)
	await _tool.seconds(CONFIRM_DELAY_S)
	_quiet()
	sounds.call(&"hear", EventBossDefeated.new(), UnifiedSession.EVENT_EMITTED, 2001)
	sounds.call(&"hear", EventMinionHit.new(), UnifiedSession.EVENT_EMITTED, 2002)
	sounds.call(&"hear", EventBossDefeated.new(), UnifiedSession.EVENT_CANCELLED, 2001)
	sounds.call(&"hear", EventMinionHit.new(), UnifiedSession.EVENT_CANCELLED, 2002)
	_expect(_fading(&"boss_death") and _busy(&"hit") == 1, "a cancelled event fades its lingering sound, not an instant one", SOUNDS)
	await _tool.seconds(FADE_WAIT_S)
	_expect(not _playing(&"boss_death"), "a cancelled event's lingering sound is silent after %.2f s" % FADE_WAIT_S, SOUNDS)
	stung.clear()
	var before: StringName = music.get(&"context")
	sounds.call(&"hear", EventBossStage.new(), UnifiedSession.EVENT_EMITTED, 3001)
	sounds.call(&"hear", EventRunBegan.new(), UnifiedSession.EVENT_EMITTED, 3002)
	var context: StringName = music.get(&"context")
	_expect(stung.is_empty() and context == before, "the news waits for CONFIRMED (stung %s, context %s)"
		% [stung, context], SOUNDS)
	sounds.call(&"hear", EventBossStage.new(), UnifiedSession.EVENT_CONFIRMED, 3001)
	sounds.call(&"hear", EventRunBegan.new(), UnifiedSession.EVENT_CONFIRMED, 3002)
	context = music.get(&"context")
	_expect(stung == [&"boss_stage", &"run_began"] and context == &"king",
		"confirmed, the stingers ring and the King's fight begins (stung %s, context %s)" % [stung, context], SOUNDS)
	_quiet()
	_sfx.disconnect(&"played", on_played)
	music.disconnect(&"stung", on_stung)
	sounds.free()  # leaving the tree, it hands the music back to the title
	context = music.get(&"context")
	_expect(context == &"title", "Sounds leaving play gives the music the title's context", SOUNDS)
	var sfx_sounds: Dictionary = _sfx.get(&"sounds")
	var stingers: Dictionary = music.get(&"stingers")
	_check_names(sfx_sounds, stingers)
	_sfx = null


## Every sound or stinger sounds.gd names (its &"" literals) is one Sfx or Music has.
func _check_names(sfx_sounds: Dictionary, stingers: Dictionary) -> void:
	var names := RegEx.create_from_string("&\"(\\w+)\"")
	for found: RegExMatch in names.search_all(FileAccess.get_file_as_string(SOUNDS)):
		var sound: StringName = found.get_string(1)
		if not sfx_sounds.has(sound) and not stingers.has(sound):
			_problem("plays %s, which neither Sfx nor Music has" % sound, SOUNDS)


func _check_music() -> void:
	var music: Node = (load(MUSIC) as PackedScene).instantiate()
	var tracks: Dictionary[StringName, AudioStream] = {&"floor": _silence(TEST_SOUND_S)}
	music.set(&"tracks", tracks)
	_tool.root.add_child(music)
	music.call(&"set_context", &"floor")
	var playing: AudioStream = music.call(&"track")
	_expect(playing == tracks[&"floor"], "a context with a track plays it", MUSIC)
	music.call(&"set_context", &"hub")
	playing = music.call(&"track")
	_expect(playing == null, "a missing track is silence over the bed", MUSIC)
	music.call(&"close")
	music.free()


## A fresh Sfx in the tree, its sounds the test's: `hit`, `roar`, `action`, `long_a`, `long_b`, `crowd_0` to
## `crowd_15` and `critical_0` to `critical_15`, each TEST_SOUND_S of silence.
func _fresh_sfx() -> void:
	_free_sfx()
	var silence: AudioStream = _silence(TEST_SOUND_S)
	var test_sounds: Dictionary[StringName, AudioStream] = {&"hit": silence, &"roar": silence, &"action": silence,
		&"long_a": silence, &"long_b": silence}
	for i: int in 16:
		test_sounds[StringName("crowd_%d" % i)] = silence
		test_sounds[StringName("critical_%d" % i)] = silence
	_sfx = (load(SFX) as PackedScene).instantiate()
	_sfx.set(&"sounds", test_sounds)
	_tool.root.add_child(_sfx)


## Stops every world voice of the Sfx under test: a headless engine never plays a sound to its end (its voices would
## stay busy, and the next check's sounds be dropped).
func _quiet() -> void:
	for player: Node in _sfx.find_children("*", "AudioStreamPlayer3D", false, false):
		(player as AudioStreamPlayer3D).stop()


func _free_sfx() -> void:
	if _sfx != null:
		_sfx.free()
		_sfx = null


## `seconds` of 16-bit mono silence.
static func _silence(seconds: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 11025
	var data := PackedByteArray()
	data.resize(int(seconds * 11025.0) * 2)
	stream.data = data
	return stream


func _voices() -> Array[Dictionary]:
	var voices: Array[Dictionary] = _sfx.call(&"world_voices")
	return voices


## The voices playing `sound`, not fading out.
func _busy(sound: StringName) -> int:
	return _voices().filter(func(v: Dictionary) -> bool: return v["sound"] == sound and v["playing"] and not v["fading"]).size()


## The voices playing a sound of `priority`, not fading out.
func _busy_at(priority: int) -> int:
	return _voices().filter(func(v: Dictionary) -> bool:
		return v["priority"] == priority and v["playing"] and not v["fading"]).size()


func _playing(sound: StringName) -> bool:
	return _voices().any(func(v: Dictionary) -> bool: return v["sound"] == sound and v["playing"])


func _fading(sound: StringName) -> bool:
	return _voices().any(func(v: Dictionary) -> bool: return v["sound"] == sound and v["fading"])


func _expect(cond: bool, what: String, at: String = SFX) -> void:
	if not cond:
		_problem("expected " + what, at)


func _problem(message: String, at: String) -> void:
	problems += 1
	_tool.log_capture.add(message, at)
