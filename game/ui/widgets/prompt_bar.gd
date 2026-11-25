class_name PromptBar
extends HBoxContainer
## The menus' prompt bar: the current screen's hints ("[A] Select  [B] Back"), drawn as ActionPrompts in the glyphs of
## the device used last. A menu's hides while a dialog shows its own (Dialog.PROMPT_BARS).

## An action prompt (game/ui/widgets/action_prompt.tscn).
@export var prompt_scene: PackedScene
## Hidden while a dialog shows (a menu's bar); the dialog's own bar keeps showing.
@export var covered_by_dialogs: bool = true


func _ready() -> void:
	if covered_by_dialogs:
		add_to_group(Dialog.PROMPT_BARS)


## Hides the bar while a dialog covers it, and shows it again.
func set_covered(covered: bool) -> void:
	visible = not covered


## Shows `screen`'s hints, and follows them while it shows (a menu's screen on top: MenuStack.top_changed), no longer
## the screen's it followed before.
func follow(screen: MenuScreen) -> void:
	for connection: Dictionary in get_incoming_connections():
		var from: Signal = connection["signal"]
		if from.get_name() == &"prompts_changed":
			from.disconnect(show_prompts)
	screen.prompts_changed.connect(show_prompts)
	show_prompts(screen.prompts)


## Shows `prompts` (a MenuScreen's: an action or a space-separated group, to what it does).
func show_prompts(prompts: Dictionary[String, String]) -> void:
	for child: Node in get_children():
		remove_child(child)  # now, not at the frame's end: the old hints never show beside the new ones
		child.queue_free()
	for actions: String in prompts:
		var prompt: ActionPrompt = prompt_scene.instantiate()
		var names: Array[StringName] = []
		for action: String in actions.split(" "):
			names.append(StringName(action))
		prompt.actions = names
		prompt.text = prompts[actions]
		add_child(prompt)
