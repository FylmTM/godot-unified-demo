extends Node
## The interface's sounds (the `Sfx` autoload): Kenney's Interface Sounds on the Interface bus, from a small pool of
## voices, so two sounds at once never cut each other off.
##
## It only plays: which control makes which sound is Game's rule (every button of the game sounds when pressed, the
## focus moving between controls sounds), so no menu script plays a click by hand. The sounds are `sounds`, set in
## sfx.tscn rather than loaded by path, so the scene's dependencies say which files of the pack the game uses (the art
## checks hold every vendored file to that). The game's own sounds join in milestone 8; the first of them play here
## meanwhile: `coin`, a pickup's chime once it is confirmed (Purse), from Kenney's RPG Audio.

## A sound started (tools count them: a dialog plays one error, not two).
signal played(sound: StringName)

## How many sounds may play at once.
const VOICES: int = 4

## Every sound by name: `press`, `select`, `confirm`, `error`, `joined`, `left`; `coin`.
@export var sounds: Dictionary[StringName, AudioStream] = {}

var _voices: Array[AudioStreamPlayer] = []
## When each voice last started a sound (Time.get_ticks_usec): the oldest gives way when every voice is busy.
var _started: PackedInt64Array = []
## The app is quitting: nothing plays any more (close).
var _closed: bool = false


func _ready() -> void:
	for i: int in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"Interface"
		add_child(voice)
		_voices.append(voice)
	_started.resize(VOICES)


## Plays sound `sound` (one of `sounds`' names) on an idle voice, else on the one that started longest ago; nothing
## once the app is quitting.
func play(sound: StringName) -> void:
	if _closed:
		return
	var stream: AudioStream = sounds.get(sound)
	if stream == null:
		push_error("Sfx: no sound %s" % sound)
		return
	var index: int = 0
	for i: int in VOICES:
		if not _voices[i].playing:
			index = i
			break
		if _started[i] < _started[index]:
			index = i
	_started[index] = Time.get_ticks_usec()
	_voices[index].stream = stream
	_voices[index].play()
	played.emit(sound)


## The app is quitting (Game.quit_app): later plays are ignored, so no sound starts while the session stops every
## playback before the quit (a playback started then would be held at exit, a leak).
func close() -> void:
	_closed = true
