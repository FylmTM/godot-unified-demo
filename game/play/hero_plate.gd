class_name HeroPlate
extends PanelContainer
## One local hero on the HUD: its class and its health, dimmed while it is down. The HUD gives each local hero a
## plate, in slot order.

## How a downed hero's plate is tinted: still readable, plainly out of the fight.
const DOWN_TINT: Color = Color(1, 1, 1, 0.55)

@onready var _class: Label = %Class
@onready var _health: Label = %Health


## Shows `hero` (Unified.data.hud's).
func show_hero(hero: DataHudHero) -> void:
	_class.text = EnumClass.name(hero.class).capitalize()
	var down: bool = hero.hp <= 0
	_health.text = "Down" if down else "%d HP" % hero.hp
	modulate = DOWN_TINT if down else Color.WHITE
