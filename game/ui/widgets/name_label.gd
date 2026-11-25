class_name NameLabel
extends Label
## A player's name in a label of a fixed width (a HUD plate, a Players row, "Paused by <name>"): a name too long for it
## is cut with "..." before its couch suffix (" +1", Party.name_of), so two guests of a long-named player stay told
## apart ("Sexton of the... +1"); text before the name (show_name's `before`: "Paused by ") stays whole, on a line of its
## own when the label is too narrow for both. It fits again whenever its width changes (the interface size). Set
## `player_name`, or call show_name(), not `text`. The rule is fitted()'s, which a toast uses too.

## The whole name, as the session has it.
var player_name: String:
	get:
		return _name
	set(value):
		show_name(_before, value)

## What the label says before the name, and the name.
var _before: String = ""
var _name: String = ""


func _ready() -> void:
	resized.connect(_fit)
	theme_changed.connect(_fit)
	_fit()


## Shows `before` (kept whole: "" for a name alone, or a whole text with no name) and then `player`, cut to fit.
func show_name(before: String, player: String) -> void:
	if before == _before and player == _name:
		return
	_before = before
	_name = player
	_fit()


## `player` as it fits in `width` after `before`, in `font` at `font_size`: whole when it fits (or while `width` isn't
## known yet), else cut with "..." before its couch suffix (" +1"), never past its first letter.
static func fitted(player: String, width: float, font: Font, font_size: int, before: String = "") -> String:
	var base: String = player
	var suffix: String = ""
	var plus: int = player.rfind(" +")
	if plus > 0 and player.substr(plus + 2).is_valid_int():
		base = player.left(plus)
		suffix = player.substr(plus)
	var shown: String = player
	while width > 0.0 and base.length() > 1 and font.get_string_size(before + shown, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x > width:
		base = base.left(-1)
		shown = base.strip_edges() + "..." + suffix
	return shown


func _fit() -> void:
	var font: Font = get_theme_font(&"font")
	var font_size: int = get_theme_font_size(&"font_size")
	var shown: String = fitted(_name, size.x, font, font_size, _before)
	var one_line: float = font.get_string_size(_before + shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if _before != "" and _name != "" and size.x > 0.0 and one_line > size.x:
		text = _before.strip_edges() + "\n" + fitted(_name, size.x, font, font_size)  # too narrow: the name below
	else:
		text = _before + shown
