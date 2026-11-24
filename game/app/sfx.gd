extends Node
## The interface's sounds (the `Sfx` autoload): Kenney's Interface Sounds on the Interface bus, from a small pool of
## voices, so two sounds at once never cut each other off.
##
## No menu script plays a click by hand: every button that enters the tree is wired here once (SceneTree.node_added),
## pressing plays `press`, and the focus moving from one control to another plays `select`, so the mouse, the keyboard
## and a pad sound alike. A button that means more names its sound in its `sfx` metadata (New game's `confirm`).
## The sounds are `sounds`, set in sfx.tscn rather than loaded by path, so the scene's dependencies say which files of
## the pack the game uses (the art checks hold every vendored file to that). The game's own sounds join in milestone 8.

## How many sounds may play at once.
const VOICES: int = 4
## The metadata a button names its own sound in (one of `sounds`' names) instead of `press`.
const META_SOUND: StringName = &"sfx"

## Every sound by name: `press`, `select`, `confirm`, `error`, `joined`, `left`.
@export var sounds: Dictionary[StringName, AudioStream] = {}

var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
## The app is quitting: nothing plays any more (close).
var _closed: bool = false
## The control that had the focus, to tell a move between two controls from a screen taking it.
var _focused: Control = null


func _ready() -> void:
	for i: int in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"Interface"
		add_child(voice)
		_voices.append(voice)
	get_tree().node_added.connect(_on_node_added)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Plays sound `sound` (one of `sounds`' names) on the next voice; nothing once the app is quitting.
func play(sound: StringName) -> void:
	if _closed:
		return
	var stream: AudioStream = sounds.get(sound)
	if stream == null:
		push_error("Sfx: no sound %s" % sound)
		return
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = stream
	voice.play()


## The app is quitting (Game.quit_app): later plays are ignored, so no sound starts while the session stops every
## playback before the quit (a playback started then would be held at exit, a leak).
func close() -> void:
	_closed = true


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_pressed(button: BaseButton) -> void:
	var sound: StringName = button.get_meta(META_SOUND, &"press")
	play(sound)


## A move between two controls plays `select`; a screen taking the focus when it opens (nothing had it) is silent.
func _on_focus_changed(control: Control) -> void:
	if is_instance_valid(_focused) and _focused.is_visible_in_tree():
		play(&"select")
	_focused = control
