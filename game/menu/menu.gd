class_name Menu
extends Node
## The menu's scene: the backdrop, the menu's screens (a MenuStack with the title at its root) and the prompt bar
## under them, which shows the hints of the screen on top (as they change: a settings slot listening). New game and
## Continue open hero select; its start is the game's, on the save for a Continue.

## The settings screen (game/ui/settings/settings_screen.tscn), opened over the title.
@export var settings_scene: PackedScene
## Hero select (game/menu/hero_select.tscn), opened by New game.
@export var hero_select_scene: PackedScene

@onready var _stack: MenuStack = %Stack
@onready var _prompt_bar: PromptBar = %PromptBar
@onready var _backdrop: Backdrop = %Backdrop


func _ready() -> void:
	var title := %TitleScreen as TitleScreen
	title.settings_requested.connect(func() -> void: _stack.push(settings_scene))
	title.new_game_requested.connect(_open_hero_select.bind(null))
	title.continue_requested.connect(func() -> void: _open_hero_select(Game.saves.setup))
	_stack.top_changed.connect(_prompt_bar.follow)
	_prompt_bar.follow(_stack.top())


## Hero select over the title: its picks step the backdrop's heroes forward, and its start is the game's, on `save`
## (null: a new game).
func _open_hero_select(save: UnifiedSetup) -> void:
	var hero_select := _stack.push(hero_select_scene) as HeroSelect
	if save != null:
		hero_select.set_heading("Continue your crypt")
	hero_select.picks_changed.connect(_backdrop.feature)
	hero_select.start_requested.connect(func(party: Party) -> void: Game.start_single(party, save))
	hero_select.tree_exiting.connect(func() -> void:
		_backdrop.feature([] as Array[int])
		_backdrop.pick_view(false))
	_backdrop.feature(hero_select.picks())
	_backdrop.pick_view(true)
