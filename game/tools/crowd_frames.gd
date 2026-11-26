extends UnifiedTool
## What the crowd costs the renderer (`./uni tool --window crowd_frames -- --autostart --setup floor=arena,crowd=chase`,
## `crowd=fight --scripted` for a fight): once the crowd has gathered, the frame time with vsync off, its p99, the GPU's
## time, the draw calls and primitives, in four lights: every shadow on, the crowd casting none, the shadowed lights
## (the braziers' fires) casting none, and neither. The numbers the crowd's shadows were decided from
## (docs/review.md); headless, nothing renders and it only proves the run.

## How long the crowd gathers before the first sample, and how long each sample runs.
const SETTLE_S: float = 7.0
const SAMPLE_S: float = 4.0
const VARIANTS: Array[String] = ["all", "no_crowd_shadows", "no_light_shadows", "none"]


func _run() -> void:
	await wait_for(func() -> bool: return session != null and session.tick > 64, 30.0, "the session runs")
	if failed():
		return
	var crowd: MultiMeshInstance3D = current_scene.find_child("Minions", true, false) as MultiMeshInstance3D
	expect(crowd != null, "the play scene has its crowd")
	if failed() or DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await seconds(SETTLE_S)
	var lights: Array[Light3D] = []
	for found: Node in current_scene.find_children("*", "Light3D", true, false):
		if (found as Light3D).shadow_enabled:
			lights.append(found as Light3D)
	var casts: GeometryInstance3D.ShadowCastingSetting = crowd.cast_shadow
	result["shadowed_lights"] = lights.size()
	for variant: String in VARIANTS:
		var crowd_off: bool = variant in ["no_crowd_shadows", "none"]
		crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if crowd_off else casts
		for light: Light3D in lights:
			light.shadow_enabled = variant not in ["no_light_shadows", "none"]
		await seconds(0.5)
		result[variant] = await _sample()
		step(variant)


## SAMPLE_S of frames: their rate and mean, their p99, the GPU's median time, the main loop's process time, what the
## last one drew, and the host's view work a frame (all of it; the MultiMeshes' buffers alone) and a fill's time.
func _sample() -> Dictionary:
	var viewport: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var times: Array[float] = []
	var gpu: Array[float] = []
	session.take_sync_stats()  # from now
	var start: int = Time.get_ticks_usec()
	var last: int = start
	while Time.get_ticks_usec() - start < SAMPLE_S * 1000000:
		await frames(1)
		var now: int = Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		last = now
	times.sort()
	gpu.sort()
	var mean: float = 0.0
	for time: float in times:
		mean += time
	mean /= times.size()
	var sync: Dictionary = session.take_sync_stats()
	var frames_shown: int = sync["frames"]
	var views_us: int = sync["total_us"]
	var build_us: int = sync["multi_build_us"]
	var upload_us: int = sync["multi_upload_us"]
	var fills: int = sync["fills"]
	var fill_total_us: float = sync["fill_us"]
	var shown: float = maxf(frames_shown, 1.0)
	var multi_us: float = build_us + upload_us
	var fill_us: float = fill_total_us / maxf(fills, 1.0)
	return {
		"fps": snappedf(1000.0 / mean, 0.1),
		"mean_ms": snappedf(mean, 0.01),
		"p99_ms": snappedf(times[int(times.size() * 0.99)], 0.01),
		"gpu_ms": snappedf(gpu[int(gpu.size() * 0.5)], 0.01),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"minions": Unified.data.hud.minions,
		"views_ms": snappedf(views_us / shown / 1000.0, 0.001),
		"multi_ms": snappedf(multi_us / shown / 1000.0, 0.001),
		"fill_us": snappedf(fill_us, 0.1),
	}
