class_name PlayerRow
extends HBoxContainer
## One player on the pause menu's Players list: their name, their hero, and Drop out for a guest on this couch.

## The player asked to drop this guest out.
signal drop_requested

@onready var _who: Label = %Who
@onready var _hero: Label = %Hero
@onready var _drop: Button = %Drop


func _ready() -> void:
	_drop.pressed.connect(drop_requested.emit)


## Shows `player_name` playing `hero_class` (EnumClass), with Drop out when `can_drop` (a guest on this couch), and
## where they play ("here", or online).
func show_player(player_name: String, hero_class: int, can_drop: bool, here: bool) -> void:
	_who.text = player_name
	_hero.text = Heroes.name_of(hero_class) + ("" if here else " · online")
	# Kept in its place when it can't drop (its room left empty), so every row's columns line up.
	_drop.disabled = not can_drop
	_drop.focus_mode = Control.FOCUS_ALL if can_drop else Control.FOCUS_NONE
	_drop.mouse_filter = Control.MOUSE_FILTER_STOP if can_drop else Control.MOUSE_FILTER_IGNORE
	_drop.modulate = Color.WHITE if can_drop else Color.TRANSPARENT


## Whether its Drop out shows (a guest on this couch).
func droppable() -> bool:
	return not _drop.disabled
