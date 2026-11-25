class_name PromptBar
extends HBoxContainer
## The menus' prompt bar: the current screen's hints ("[A] Select  [B] Back"), drawn as ActionPrompts in the glyphs of
## the device used last.

## An action prompt (game/ui/widgets/action_prompt.tscn).
@export var prompt_scene: PackedScene


## Shows `prompts` (a MenuScreen's: an action or a space-separated group, to what it does).
func show_prompts(prompts: Dictionary[String, String]) -> void:
	for child: Node in get_children():
		child.queue_free()
	for actions: String in prompts:
		var prompt: ActionPrompt = prompt_scene.instantiate()
		var names: Array[StringName] = []
		for action: String in actions.split(" "):
			names.append(StringName(action))
		prompt.actions = names
		prompt.text = prompts[actions]
		add_child(prompt)
