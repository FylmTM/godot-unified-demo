class_name NameLabel
extends Label
## A player's name in a label of a fixed width (a HUD plate, a Players row): a name too long for it is cut with "..."
## before its couch suffix (" +1", Party.name_of), so two guests of a long-named player stay told apart ("Sexton of
## the... +1"). It fits again whenever its width changes (the interface size). Set `player_name`, not `text`.

## The whole name, as the session has it.
var player_name: String = "":
	set(value):
		if value != player_name:
			player_name = value
			_fit()


func _ready() -> void:
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	var font: Font = get_theme_font(&"font")
	var font_size: int = get_theme_font_size(&"font_size")
	var base: String = player_name
	var suffix: String = ""
	var plus: int = player_name.rfind(" +")
	if plus > 0 and player_name.substr(plus + 2).is_valid_int():
		base = player_name.left(plus)
		suffix = player_name.substr(plus)
	var shown: String = player_name
	while size.x > 0.0 and base.length() > 1 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x > size.x:
		base = base.left(-1)
		shown = base.strip_edges() + "..." + suffix
	text = shown
