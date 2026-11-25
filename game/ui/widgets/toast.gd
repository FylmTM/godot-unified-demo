class_name Toast
extends PanelContainer
## One short line on a dark plate that fades in, stays a few seconds, fades out and frees itself: news that needs no
## answer ("Sexton joined (Mage)"). Toasts stacks them.

## How long it fades in and out, and how long it stays fully shown between, in seconds.
const FADE_S: float = 0.25
const SHOWN_S: float = 3.0


func _ready() -> void:
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, ^"modulate:a", 1.0, FADE_S)
	tween.tween_interval(SHOWN_S)
	tween.tween_property(self, ^"modulate:a", 0.0, FADE_S)
	tween.tween_callback(queue_free)


## What it says: `player`'s name (cut to one line of a toast `width` wide, by NameLabel's rule, keeping its "+1"),
## then `text`; or `text` alone when `player` is "".
func set_text(text: String, player: String = "", width: float = 0.0) -> void:
	var label: Label = %Text as Label
	if player == "":
		label.text = text
		return
	var room: float = width - get_theme_stylebox(&"panel").get_minimum_size().x
	var font_size: int = label.get_theme_font_size(&"font_size")
	label.text = NameLabel.fitted(player, room, label.get_theme_font(&"font"), font_size) + text
