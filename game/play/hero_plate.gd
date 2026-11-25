class_name HeroPlate
extends PanelContainer
## One local hero on the HUD: its portrait, its player's name and its class above its health, which leads (a bar of hp
## of hp_max, the number on it, "Down" while it is down), and the controls of its player's device under them: the
## keyboard's for the keyboard player, a guest's own pad's. Every plate's bar is one length, whatever its names say.
##
## The hints show as Settings.hints says: Briefly (the default) shows them for HINTS_S after the plate's player joins or
## turns to another kind of device (a pad's family, or the keyboard), so four players' plates don't cover the crypt;
## Always and Off as they say. The HUD gives each local hero a plate, in slot order.

## How long the hints stay up after a join or a change of device, in seconds (Settings.Hints.BRIEFLY).
const HINTS_S: float = 6.0
## How a downed hero's plate is tinted: still readable, plainly out of the fight.
const DOWN_TINT: Color = Color(1, 1, 1, 0.55)

## The player and the device family the hints last showed for (-1: none yet), and until when they show (msec).
var _player: int = -1
var _family: int = -1
var _hints_until: int = 0

@onready var _portrait: TextureRect = %Portrait
@onready var _who: Label = %Who
@onready var _class: Label = %Class
@onready var _health: ProgressBar = %Health
@onready var _amount: Label = %Amount
@onready var _hints: GridContainer = %Hints


func _ready() -> void:
	Settings.changed.connect(func(setting: StringName) -> void:
		if setting == &"hints":
			_show_hints())  # at once, as every setting applies


func _process(_delta: float) -> void:
	_show_hints()


## Shows `hero` (Unified.data.hud's), played by local player `local`.
func show_hero(hero: DataHudHero, local: int) -> void:
	_portrait.texture = Heroes.portrait(hero.class)
	_who.text = Unified.session.get_player_name(hero.player)
	_class.text = Heroes.name_of(hero.class)
	var down: bool = hero.hp <= 0
	_health.max_value = maxi(hero.hp_max, 1)
	_health.value = hero.hp
	_amount.text = "Down" if down else str(hero.hp)
	modulate = DOWN_TINT if down else Color.WHITE
	var family: int = Prompts.family_of_local(local)
	if hero.player != _player or family != _family:
		_player = hero.player
		_family = family
		_hints_until = Time.get_ticks_msec() + roundi(HINTS_S * 1000.0)
	for hint: Node in _hints.get_children():
		var prompt := hint as ActionPrompt
		if prompt.local != local:
			prompt.local = local
			prompt.refresh()
	_show_hints()


## Whether the hints show now (Settings.hints): the walk asks.
func hints_shown() -> bool:
	return _hints.visible


func _show_hints() -> void:
	match Settings.hints:
		Settings.Hints.ALWAYS:
			_hints.visible = true
		Settings.Hints.NEVER:
			_hints.visible = false
		_:
			_hints.visible = Time.get_ticks_msec() < _hints_until
