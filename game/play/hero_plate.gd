class_name HeroPlate
extends PanelContainer
## One local hero on the HUD: its portrait, its health leading (a bar of hp of hp_max, the number on it, "Down" while
## it is down), its class quieter beside, and the controls of its player's device under them (Settings.show_hints):
## the keyboard's for the keyboard player, a guest's own pad's. Every plate is as wide as the widest set of hints, so
## plates line up whatever their devices. The HUD gives each local hero a plate, in slot order.

## How a downed hero's plate is tinted: still readable, plainly out of the fight.
const DOWN_TINT: Color = Color(1, 1, 1, 0.55)

@onready var _portrait: TextureRect = %Portrait
@onready var _health: ProgressBar = %Health
@onready var _amount: Label = %Amount
@onready var _class: Label = %Class
@onready var _hints: HBoxContainer = %Hints


func _ready() -> void:
	_hints.visible = Settings.show_hints
	Settings.changed.connect(func(setting: StringName) -> void:
		if setting == &"show_hints":
			_hints.visible = Settings.show_hints)


## Shows `hero` (Unified.data.hud's), played by local player `local`.
func show_hero(hero: DataHudHero, local: int) -> void:
	_portrait.texture = Heroes.portrait(hero.class)
	_class.text = Heroes.name_of(hero.class)
	var down: bool = hero.hp <= 0
	_health.max_value = maxi(hero.hp_max, 1)
	_health.value = hero.hp
	_amount.text = "Down" if down else str(hero.hp)
	modulate = DOWN_TINT if down else Color.WHITE
	for hint: Node in _hints.get_children():
		var prompt := hint as ActionPrompt
		if prompt.local != local:
			prompt.local = local
			prompt.refresh()
