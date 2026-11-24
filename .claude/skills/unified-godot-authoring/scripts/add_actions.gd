extends UnifiedTool
## Adds input actions to project.godot, or replaces them: a key by its place, a mouse button, a joypad button and a
## stick direction. Change the actions, run it with `./uni tool <this file>`.


func _run() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G  # the key's place, whatever the keyboard layout
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	var button := InputEventJoypadButton.new()
	button.device = -1  # every joypad: a new event's 0 is the first one only
	button.button_index = JOY_BUTTON_Y
	var stick := InputEventJoypadMotion.new()
	stick.device = -1
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = -1.0
	ProjectSettings.set_setting("input/throw", {"deadzone": 0.2, "events": [key, mouse, button]})
	ProjectSettings.set_setting("input/move_left", {"deadzone": 0.2, "events": [stick]})
	expect(ProjectSettings.save() == OK, "saved project.godot")
