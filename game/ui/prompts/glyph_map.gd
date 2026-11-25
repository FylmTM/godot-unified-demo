class_name GlyphMap
extends Resource
## One family of control prompts (keyboard and mouse, Xbox, PlayStation, Switch): Kenney's Input Prompts font and
## which of its characters draws which glyph. The glyphs are baked from the map the pack ships beside its font
## (`<font>_map.txt`, vendored unchanged as the source) by game/tools/bake_glyphs.gd, so the game loads a resource
## and an export needs nothing it would leave out; the app checks hold the baked map to its source.

## The family's font.
@export var font: FontFile
## Each glyph's name (`xbox_button_a`) to its character in the font.
@export var glyphs: Dictionary[String, String] = {}
## The map this was baked from (the pack's `<font>_map.txt`).
@export var source: String = ""


## The glyphs a pack's map lists: `name: U+E015` lines, a glyph's name to its character.
static func parse(text: String) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for line: String in text.split("\n"):
		var parts: PackedStringArray = line.strip_edges().split(": U+")
		if parts.size() == 2 and parts[1].is_valid_hex_number():
			out[parts[0]] = String.chr(parts[1].hex_to_int())
	return out
