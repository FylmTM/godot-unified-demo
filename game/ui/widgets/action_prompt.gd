class_name ActionPrompt
extends HBoxContainer
## An action's glyph and what it does ("[A] Select", "[W A S D] Move"), for one local player's device: the HUD's
## hints, the menus' prompt bar. It follows Prompts.changed (the device used last, a pad connected, the style, the
## bindings) and the session's local players (a couch guest fixes player 0's device), and redraws only when what it
## shows differs, and only while it is on screen (a hidden prompt catches up when it shows). A binding with no glyph
## shows its name in text. A prompt font draws its glyph in the middle of a line twice its height, so the glyph sits
## in a box of the row's height and overflows it, rather than the line growing the row.

## The action, or the actions that make one control (the four moves); `aim` for the aim (the mouse, the right stick).
@export var actions: Array[StringName] = []
## What the action does, after its glyph ("" shows the glyph alone).
@export var text: String = ""
## The local player whose device the glyph is for (0: the first; the menus' too).
@export var local: int = 0
## On parchment (a seat card): ink, rather than the cream that reads over the world.
@export var ink: bool = false
## The words' look when not the usual (HudSmall: a hero plate's hints).
@export var text_variation: StringName = &""
## One device's glyphs whoever plays: a pad's id (in that pad's family), or UnifiedSession.DEVICE_KEYBOARD (-2) for
## the keyboard's; -1 follows `local`. The join hint speaks to a pad nobody plays; a seat card to its seat's device.
@export var device: int = -1

## What the prompt shows now: its family and glyphs (or words), to redraw only on a change.
var _shown: String = ""

@onready var _glyph_box: Control = %GlyphBox
@onready var _glyphs: Label = %Glyphs
@onready var _text: Label = %Text


func _ready() -> void:
	_text.theme_type_variation = text_variation if text_variation != &"" else &"Ink" if ink else &"HudText"
	Prompts.changed.connect(refresh)
	Unified.session.local_players_changed.connect(refresh)
	visibility_changed.connect(refresh)
	refresh()


## Draws the glyphs again if they differ from those shown (they follow the device, the style and the bindings by
## themselves; a caller changing `local` or `device` calls this).
func refresh() -> void:
	if not is_visible_in_tree():
		return
	var family: Prompts.Family = Prompts.family_of_local(local)
	if device == UnifiedSession.DEVICE_KEYBOARD:
		family = Prompts.Family.KEYBOARD
	elif device >= 0:
		family = Prompts.pad_family(device)
	var glyphs: String = Prompts.glyphs(actions, family)
	var words: String = Prompts.text_of(actions, family) if glyphs == "" else ""
	var shown: String = "%d %s %s %s" % [family, glyphs, words, text]
	if shown == _shown:
		return
	_shown = shown
	if glyphs != "":
		_glyphs.theme_type_variation = &"InkGlyph" if ink else &"PromptGlyph"
		_glyphs.add_theme_font_override(&"font", Prompts.font(family))
		_glyphs.text = glyphs
	else:
		_glyphs.theme_type_variation = _text.theme_type_variation
		_glyphs.remove_theme_font_override(&"font")
		_glyphs.text = "[%s]" % words
	_glyph_box.custom_minimum_size.x = _glyphs.get_minimum_size().x
	_text.text = text
	_text.visible = text != ""
