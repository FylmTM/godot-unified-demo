class_name Menu
extends Node
## The menu's scene: the backdrop, the menu's screens (a MenuStack with the title at its root) and the prompt bar
## under them, which shows the hints of the screen on top (as they change: a settings slot listening).
##
## Every start goes through hero select, whatever asked for it: New game, Continue (on the slot's save), and Play
## together's host (a new crypt or the saved one: HostCryptScreen, when there is one) and joins (a code, an address,
## the last game). A start that fails before it plays (Game.start_failed) comes back to the screen it was asked from,
## what was typed there kept, the dialog over it saying why.

## The settings screen (game/ui/settings/settings_screen.tscn), opened over the title.
@export var settings_scene: PackedScene
## Hero select (game/menu/hero_select.tscn), opened by every start.
@export var hero_select_scene: PackedScene
## Play together and the screens it opens (game/menu/): the crypt a host opens, a code to join, an address to join.
@export var play_together_scene: PackedScene
@export var host_crypt_scene: PackedScene
@export var join_code_scene: PackedScene
@export var join_address_scene: PackedScene

@onready var _stack: MenuStack = %Stack
@onready var _prompt_bar: PromptBar = %PromptBar
@onready var _backdrop: Backdrop = %Backdrop


func _ready() -> void:
	var title := %TitleScreen as TitleScreen
	title.settings_requested.connect(func() -> void: _stack.push(settings_scene))
	title.new_game_requested.connect(func() -> void:
		_open_hero_select("Choose your heroes", func(party: Party) -> void: Game.start_single(party)))
	title.continue_requested.connect(_continue)
	title.play_together_requested.connect(_open_play_together)
	Game.continue_wanted.connect(_continue)
	Game.start_failed.connect(_back_from_hero_select)
	_stack.top_changed.connect(_prompt_bar.follow)
	_prompt_bar.follow(_stack.top())


## Hero select on the slot's save (the title's Continue, or a joiner continuing its host's alone).
func _continue() -> void:
	var save: UnifiedSetup = Game.saves.setup
	_open_hero_select("Continue your crypt", func(party: Party) -> void: Game.start_single(party, save))


func _open_play_together() -> void:
	var screen := _stack.push(play_together_scene) as PlayTogetherScreen
	screen.host_requested.connect(_host)
	screen.join_code_requested.connect(func() -> void:
		var join := _stack.push(join_code_scene) as JoinCodeScreen
		join.join_requested.connect(_join.bind(true)))
	screen.join_address_requested.connect(func() -> void:
		var join := _stack.push(join_address_scene) as JoinAddressScreen
		join.join_requested.connect(_join.bind(false)))
	screen.rejoin_requested.connect(_join)


## Hosts a game (`online`: by a lobby code): on the saved run or a new one in the hub (asked while the slot holds a run;
## a new one over it asks first, as the title's New game does).
func _host(online: bool) -> void:
	var host: Callable = func(save: UnifiedSetup) -> void:
		_open_hero_select("Host a crypt", func(party: Party) -> void: Game.start_host(party, save, online))
	if not Game.saves.has_run():
		host.call(null)
		return
	var crypt := _stack.push(host_crypt_scene) as HostCryptScreen
	crypt.chosen.connect(func(save: UnifiedSetup) -> void:
		if save != null:
			host.call(save)
			return
		Game.ask("Start a new crypt?", "Your saved run (%s) is replaced when the new run begins."
			% Game.saves.summary(), "New crypt", "Back", func(confirmed: bool) -> void:
				if confirmed:
					host.call(null)))


## Joins `target` (a lobby code when `online`, else an address) once the couch here has picked its heroes.
func _join(target: String, online: bool) -> void:
	_open_hero_select("Join %s" % target, func(party: Party) -> void: Game.start_join(party, target, online))


## Hero select over the title, under `heading`: its picks step the backdrop's heroes forward, and its start calls
## `start` with the party.
func _open_hero_select(heading: String, start: Callable) -> void:
	var hero_select := _stack.push(hero_select_scene) as HeroSelect
	hero_select.set_heading(heading)
	hero_select.picks_changed.connect(_backdrop.feature)
	hero_select.start_requested.connect(start)
	hero_select.tree_exiting.connect(func() -> void:
		_backdrop.feature([] as Array[int])
		_backdrop.pick_view(false))
	_backdrop.feature(hero_select.picks())
	_backdrop.pick_view(true)


## A start failed: hero select goes, so the screen it was asked from shows again (the dialog says why).
func _back_from_hero_select() -> void:
	if _stack.top() is HeroSelect:
		_stack.pop()
