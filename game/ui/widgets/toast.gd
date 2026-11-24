class_name Toast
extends PanelContainer
## One short line on a dark plate that fades in, stays a few seconds, fades out and frees itself: news that needs no
## answer ("Mira joined"). Toasts stacks them.

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


## The line it shows; set before it enters the tree.
func set_text(text: String) -> void:
	(%Text as Label).text = text
