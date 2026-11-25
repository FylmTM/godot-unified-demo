extends UnifiedTool
## Bakes the control prompts' glyph maps (`./uni tool bake_glyphs`): each family's font and the map Kenney's Input
## Prompts ship beside it (`<font>_map.txt`) become a GlyphMap resource in game/ui/prompts/, which the Prompts
## autoload loads. Run it after the pack is updated; the app checks fail while a baked map differs from its source.

## Each family's resource and the font it is baked from.
const FAMILIES: Dictionary[String, String] = {
	"res://game/ui/prompts/keyboard.tres": "res://assets/kenney/input_prompts/kenney_input_keyboard_&_mouse.ttf",
	"res://game/ui/prompts/xbox.tres": "res://assets/kenney/input_prompts/kenney_input_xbox_series.ttf",
	"res://game/ui/prompts/playstation.tres": "res://assets/kenney/input_prompts/kenney_input_playstation_series.ttf",
	"res://game/ui/prompts/switch.tres": "res://assets/kenney/input_prompts/kenney_input_nintendo_switch.ttf",
}


func _run() -> void:
	for target: String in FAMILIES:
		var font_path: String = FAMILIES[target]
		var map := GlyphMap.new()
		map.font = load(font_path)
		map.source = font_path.get_basename() + "_map.txt"
		map.glyphs = GlyphMap.parse(FileAccess.get_file_as_string(map.source))
		expect(not map.glyphs.is_empty(), "%s lists glyphs" % map.source)
		expect(ResourceSaver.save(map, target) == OK, "saved " + target)
		step("%s: %d glyphs" % [target.get_file(), map.glyphs.size()])
