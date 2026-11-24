extends UnifiedTool
## Writes a UI scene: a full-window Control that lets clicks through, and a centred panel with a title and a button
## that its script finds as %Title and %Start. Change it, run it with `./uni tool <this file>`.

const PATH := "res://game/ui/lobby.tscn"

var scene := Control.new()


func _run() -> void:
	scene.name = "Lobby"
	scene.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a full-window STOP eats every click meant for what is behind
	var panel := PanelContainer.new()
	_add(scene, panel, "Panel")
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH  # it grows to its content from the centre
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var rows := VBoxContainer.new()
	_add(panel, rows, "Rows")
	var title := Label.new()
	title.text = "Lobby"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add(rows, title, "Title", true)
	var start := Button.new()
	start.text = "Start"
	start.custom_minimum_size = Vector2(200, 40)
	_add(rows, start, "Start", true)
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var packed := PackedScene.new()
	expect(packed.pack(scene) == OK and ResourceSaver.save(packed, PATH) == OK, "saved " + PATH)
	scene.free()


## Adds `child` under `parent`, owned by the scene's root (pack() saves only what it owns); `unique`: found as %Name.
func _add(parent: Node, child: Node, child_name: String, unique := false) -> void:
	child.name = child_name
	parent.add_child(child)
	child.owner = scene
	child.unique_name_in_owner = unique
