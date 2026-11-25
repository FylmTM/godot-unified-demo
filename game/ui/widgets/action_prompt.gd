class_name ActionPrompt
extends HBoxContainer
## An action's glyph and what it does ("[A] Select", "[W A S D] Move"), for one local player's device: the HUD's
## hints, the menus' prompt bar. It redraws when Prompts says a glyph may differ (the device used last, a pad
## connected, the style, the bindings) and when the session's local players change (a couch guest fixes player 0's
## device). A binding with no glyph shows its name in text. A prompt font draws its glyph in the middle of a line
## twice its height, so the glyph sits in a box of the row's height and overflows it, rather than the line growing
## the row.

## The action, or the actions that make one control (the four moves); `aim` for the aim (the mouse, the right stick).
@export var actions: Array[StringName] = []
## What the action does, after its glyph ("" shows the glyph alone).
@export var text: String = ""
## The local player whose device the glyph is for (0: the first; the menus' too).
@export var local: int = 0
## On parchment: ink, rather than the cream that reads over the world.
@export var ink: bool = false
## Always a pad's glyph (the pad used last's family): the join hint, which speaks to a pad nobody plays.
@export var pad: bool = false

@onready var _glyph_box: Control = %GlyphBox
@onready var _glyphs: Label = %Glyphs
@onready var _text: Label = %Text


func _ready() -> void:
	_text.theme_type_variation = &"Ink" if ink else &"HudText"
	_glyphs.add_theme_color_override(&"font_color", get_theme_color(&"font_color", _text.theme_type_variation))
	Prompts.changed.connect(refresh)
	Unified.session.local_players_changed.connect(refresh)
	refresh()


## Draws the glyphs again (they follow the device, the style and the bindings by themselves).
func refresh() -> void:
	var family: Prompts.Family = Prompts.pad_family(Prompts.last_pad) if pad else Prompts.family_of_local(local)
	var glyphs: String = Prompts.glyphs(actions, family)
	if glyphs != "":
		_glyphs.add_theme_font_override(&"font", Prompts.font(family))
		_glyphs.text = glyphs
	else:
		_glyphs.remove_theme_font_override(&"font")
		_glyphs.text = "[%s]" % Prompts.text_of(actions[0], family) if not actions.is_empty() else ""
	_glyph_box.custom_minimum_size.x = _glyphs.get_minimum_size().x
	_text.text = text
	_text.visible = text != ""
