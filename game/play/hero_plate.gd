class_name HeroPlate
extends PanelContainer
## One local hero on the HUD: its class and its health, dimmed while it is down, and the controls of its player's
## device under them (Settings.show_hints): the keyboard's for the keyboard player, a guest's own pad's. The HUD gives
## each local hero a plate, in slot order.

## How a downed hero's plate is tinted: still readable, plainly out of the fight.
const DOWN_TINT: Color = Color(1, 1, 1, 0.55)

@onready var _class: Label = %Class
@onready var _health: Label = %Health
@onready var _hints: HBoxContainer = %Hints


func _ready() -> void:
	_hints.visible = Settings.show_hints
	Settings.changed.connect(func(setting: StringName) -> void:
		if setting == &"show_hints":
			_hints.visible = Settings.show_hints)


## Shows `hero` (Unified.data.hud's), played by local player `local`.
func show_hero(hero: DataHudHero, local: int) -> void:
	_class.text = EnumClass.name(hero.class).capitalize()
	var down: bool = hero.hp <= 0
	_health.text = "Down" if down else "%d HP" % hero.hp
	modulate = DOWN_TINT if down else Color.WHITE
	for hint: Node in _hints.get_children():
		var prompt := hint as ActionPrompt
		if prompt.local != local:
			prompt.local = local
			prompt.refresh()
