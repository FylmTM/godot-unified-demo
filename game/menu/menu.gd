class_name Menu
extends Node
## The menu's scene: the backdrop, the menu's screens (a MenuStack with the title at its root) and the prompt bar
## under them, which shows the screen on top's hints.

## The settings screen (game/ui/settings/settings_screen.tscn), opened over the title.
@export var settings_scene: PackedScene

@onready var _stack: MenuStack = %Stack
@onready var _prompt_bar: PromptBar = %PromptBar


func _ready() -> void:
	(%TitleScreen as TitleScreen).settings_requested.connect(func() -> void: _stack.push(settings_scene))
	_stack.top_changed.connect(func(screen: MenuScreen) -> void: _prompt_bar.show_prompts(screen.prompts))
	_prompt_bar.show_prompts(_stack.top().prompts)
