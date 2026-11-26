class_name HeroPlate
extends PanelContainer
## One local hero on the HUD: its portrait, its player's name, its class and its ability's pip (filling as the cooldown
## runs, full and bright when ready) above its health, which leads (a bar of hp of hp_max, the number on it, "Down"
## while it is down), its boons under it (each it holds, with a + per rank: Hud_Hero.boons), and the controls of its
## player's device under them: the keyboard's for the keyboard player, a guest's own pad's, the ability's named for what
## it does in the hero's class. Every plate's bar is one length, whatever its names say.
##
## The hints show as Settings.hints says: Briefly (the default) shows them for HINTS_S after the plate's player joins or
## turns to another kind of device (a pad's family, or the keyboard), so four players' plates don't cover the crypt;
## Always and Off as they say. The HUD gives each local hero a plate, in slot order.

## How long the hints stay up after a join or a change of device, in seconds (Settings.Hints.BRIEFLY).
const HINTS_S: float = 6.0
## How a downed hero's plate is tinted: still readable, plainly out of the fight.
const DOWN_TINT: Color = Color(1, 1, 1, 0.55)
## How the ability's pip is tinted while its cooldown runs: the fill dimmer than a ready one's.
const PIP_COOLING: Color = Color(0.6, 0.6, 0.6, 0.8)
## What each class's ability does, as its hint says (EnumClass).
const ABILITY_NAMES: Dictionary[int, String] = {
	EnumClass.KNIGHT: "Block", EnumClass.BARBARIAN: "Heave", EnumClass.MAGE: "Fireball", EnumClass.ROGUE: "Roll",
}

## The player and the device family the hints last showed for (-1: none yet), and until when they show (msec).
var _player: int = -1
var _family: int = -1
var _hints_until: int = 0
## The local player whose hero this plate shows.
var _local: int = 0

@onready var _portrait: TextureRect = %Portrait
@onready var _who: NameLabel = %Who
@onready var _class: Label = %Class
@onready var _health: ProgressBar = %Health
@onready var _amount: Label = %Amount
@onready var _hints: GridContainer = %Hints
@onready var _ability_pip: ProgressBar = %AbilityPip
@onready var _ability_hint: ActionPrompt = %Ability
@onready var _boons: Label = %Boons


func _ready() -> void:
	Settings.changed.connect(func(setting: StringName) -> void:
		if setting == &"hints":
			_show_hints())  # at once, as every setting applies
	Prompts.changed.connect(_note_device)


func _process(_delta: float) -> void:
	_show_hints()


## Shows `hero` (Unified.data.hud's), played by local player `local`.
func show_hero(hero: DataHudHero, local: int) -> void:
	_portrait.texture = Heroes.portrait(hero.class)
	_who.player_name = Unified.session.get_player_name(hero.player)
	_class.text = Heroes.name_of(hero.class)
	_health.max_value = maxi(hero.hp_max, 1)
	_health.value = hero.hp
	_amount.text = "Down" if hero.down else str(hero.hp)
	modulate = DOWN_TINT if hero.down else Color.WHITE
	_show_boons(hero.boons)
	_ability_pip.value = hero.ability
	_ability_pip.modulate = Color.WHITE if hero.ability >= 255 else PIP_COOLING
	var ability_name: String = ABILITY_NAMES.get(hero.class, "Ability")
	if _ability_hint.text != ability_name:
		_ability_hint.text = ability_name
		_ability_hint.refresh()
	_local = local
	if hero.player != _player:
		_player = hero.player
		_family = -1
	_note_device()
	for hint: Node in _hints.get_children():
		var prompt := hint as ActionPrompt
		if prompt.local != local:
			prompt.local = local
			prompt.refresh()
	_show_hints()


## The player turned to another kind of device (or just arrived): the hints show for HINTS_S. Asked as the HUD's data
## changes and as Prompts says the devices changed, so a change shows at once even while the crypt stands still.
func _note_device() -> void:
	var family: int = Prompts.family_of_local(_local)
	if _player >= 0 and family != _family:
		_family = family
		_hints_until = Time.get_ticks_msec() + roundi(HINTS_S * 1000.0)
		_show_hints()


## Each boon the hero holds, named, a + a rank ("Keen Edge ++"); none: the line hides.
func _show_boons(ranks: Array) -> void:
	var held: PackedStringArray = []
	for boon: int in ranks.size():
		var rank: int = ranks[boon]
		if rank > 0:
			held.append("%s %s" % [BoonPanel.NAMES.get(boon, "?"), "+".repeat(rank)])
	_boons.text = "   ".join(held)
	_boons.visible = not held.is_empty()


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
