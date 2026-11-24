extends UnifiedTool
## Takes the look-dev shots: opens game/lookdev/lookdev.tscn, shows each of its camera shots, lets the lights and
## particles settle, and saves a screenshot of each (`./uni tool lookdev --window --shots`, into
## .out/shots/lookdev/). With `--frames` it also logs the frame times.
##
## Per shot, the result line carries what the renderer drew (draw calls, objects, primitives), so a look change that
## costs too much shows in numbers, not only in the pictures. Headless (no --window) nothing renders: it only proves
## the scene loads and shows every shot, without waiting.

## How long a shot settles before it is taken: the fire particles fill in.
const SETTLE_S: float = 1.2


func _run() -> void:
	var lookdev: Lookdev = (load("res://game/lookdev/lookdev.tscn") as PackedScene).instantiate()
	root.add_child(lookdev)
	current_scene = lookdev
	await frames(2)
	var rendering: bool = DisplayServer.get_name() != "headless"
	var counts: Dictionary[String, Dictionary] = {}
	for index: int in lookdev.shots.size():
		var shot_name: String = lookdev.shots[index].shot_name
		lookdev.show_shot(index)
		if not rendering:
			await frames(1)
			continue
		await seconds(SETTLE_S)
		frame_tag(shot_name)
		await shot(shot_name)
		counts[shot_name] = {
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		}
		step("shot " + shot_name)
	result["shots"] = counts
