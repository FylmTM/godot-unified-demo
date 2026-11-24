extends Control

@onready var swatch: ColorRect = %Swatch
@onready var players_label: Label = %Players
@onready var balls_label: Label = %Balls
@onready var paused_label: Label = %Paused


func _ready() -> void:
	Unified.data.hud.changed.connect(_on_hud_changed)
	_on_hud_changed()


# Session data is the newest prediction, so it can roll back: what must be final (a win) comes from a CONFIRMED event,
# or the HUD flickers (unified/docs/gameplay.md).
func _on_hud_changed() -> void:
	swatch.color = Unified.data.hud.color
	players_label.text = "Players: %d" % Unified.data.hud.players
	balls_label.text = "Balls: %d" % Unified.data.hud.balls
	paused_label.visible = Unified.data.hud.paused
