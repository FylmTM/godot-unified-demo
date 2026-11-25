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
## A pad's glyph, in that pad's family, whoever plays (-1: follow `local`): the join hint, which speaks to a pad
## nobody plays.
@export var pad_device: int = -1

## What the prompt shows now: its family and glyphs (or words), to redraw only on a change.
var _shown: String = ""

@onready var _glyph_box: Control = %GlyphBox
@onready var _glyphs: Label = %Glyphs
@onready var _text: Label = %Text


func _ready() -> void:
	Prompts.changed.connect(refresh)
	Unified.session.local_players_changed.connect(refresh)
	visibility_changed.connect(refresh)
	refresh()


## Draws the glyphs again if they differ from those shown (they follow the device, the style and the bindings by
## themselves; a caller changing `local` or `pad_device` calls this).
func refresh() -> void:
	if not is_visible_in_tree():
		return
	var family: Prompts.Family = (Prompts.pad_family(pad_device) if pad_device >= 0
		else Prompts.family_of_local(local))
	var glyphs: String = Prompts.glyphs(actions, family)
	var words: String = Prompts.text_of(actions, family) if glyphs == "" else ""
	var shown: String = "%d %s %s %s" % [family, glyphs, words, text]
	if shown == _shown:
		return
	_shown = shown
	if glyphs != "":
		_glyphs.theme_type_variation = &"PromptGlyph"
		_glyphs.add_theme_font_override(&"font", Prompts.font(family))
		_glyphs.text = glyphs
	else:
		_glyphs.theme_type_variation = _text.theme_type_variation
		_glyphs.remove_theme_font_override(&"font")
		_glyphs.text = "[%s]" % words
	_glyph_box.custom_minimum_size.x = _glyphs.get_minimum_size().x
	_text.text = text
	_text.visible = text != ""
