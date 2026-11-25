class_name Menu
extends Node
## The menu's scene: the backdrop, the menu's screens (a MenuStack with the title at its root) and the prompt bar
## under them, which shows the hints of the screen on top (as they change: a settings slot listening).

## The settings screen (game/ui/settings/settings_screen.tscn), opened over the title.
@export var settings_scene: PackedScene

@onready var _stack: MenuStack = %Stack
@onready var _prompt_bar: PromptBar = %PromptBar


func _ready() -> void:
	(%TitleScreen as TitleScreen).settings_requested.connect(func() -> void: _stack.push(settings_scene))
	_stack.top_changed.connect(_follow)
	_follow(_stack.top())


## Shows `screen`'s hints on the prompt bar, and follows them while it is on top.
func _follow(screen: MenuScreen) -> void:
	for connection: Dictionary in _prompt_bar.get_incoming_connections():
		var from: Signal = connection["signal"]
		if from.get_name() == &"prompts_changed":
			from.disconnect(_prompt_bar.show_prompts)
	screen.prompts_changed.connect(_prompt_bar.show_prompts)
	_prompt_bar.show_prompts(screen.prompts)
