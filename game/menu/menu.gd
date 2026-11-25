class_name Menu
extends Node
## The menu's scene: the backdrop, the menu's screens (a MenuStack with the title at its root) and the prompt bar
## under them, which shows the hints of the screen on top (as they change: a settings slot listening).

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
	title.new_game_requested.connect(_open_hero_select)
	_stack.top_changed.connect(_follow)
	_follow(_stack.top())


## Hero select over the title: its picks step the backdrop's heroes forward, and its start is the game's.
func _open_hero_select() -> void:
	var hero_select := _stack.push(hero_select_scene) as HeroSelect
	hero_select.picks_changed.connect(_backdrop.feature)
	hero_select.start_requested.connect(Game.start_single)
	hero_select.tree_exiting.connect(func() -> void:
		_backdrop.feature([] as Array[int])
		_backdrop.pick_view(false))
	_backdrop.feature(hero_select.picks())
	_backdrop.pick_view(true)


## Shows `screen`'s hints on the prompt bar, and follows them while it is on top.
func _follow(screen: MenuScreen) -> void:
	for connection: Dictionary in _prompt_bar.get_incoming_connections():
		var from: Signal = connection["signal"]
		if from.get_name() == &"prompts_changed":
			from.disconnect(_prompt_bar.show_prompts)
	screen.prompts_changed.connect(_prompt_bar.show_prompts)
	_prompt_bar.show_prompts(screen.prompts)
