extends UnifiedTool
## Renders each hero's portrait (`./uni tool render_portraits --window`: it needs a renderer) into
## Heroes.portrait_path(), from the hero scenes as the game poses them: head and shoulders, idling, lit as the
## look-dev scene lights a hero, on a transparent background. Run it again when a hero's look changes; the app checks
## hold every class to having one. The Knight's portrait, larger, is also the game's icon (application/config/icon,
## which the exports turn into the Windows and macOS icons).

const SIZE: int = 256
## The icon's side (pixels): the largest the macOS icon set takes from it without scaling up.
const ICON_SIZE: int = 512
const ICON: String = "res://game/icon.png"
const HEROES: String = "res://game/characters/heroes/%s.tscn"
## Where the camera stands and looks, from a hero standing at the origin facing +Z (metres): nearly face on, the head
## and shoulders filling the frame, the head a little above its middle.
const EYE: Vector3 = Vector3(0.25, 1.9, 3.9)
const TARGET: Vector3 = Vector3(0.0, 1.6, 0.0)
const FOV: float = 32.0
## How far into its idle each hero is posed (seconds): a calm moment.
const POSE_S: float = 0.6


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		fail("portraits need a renderer: run with --window")
		return
	for hero_class: int in Heroes.classes():
		var image: Image = await _render(EnumClass.name(hero_class).to_lower(), SIZE)
		if failed():
			return
		_save(image, Heroes.portrait_path(hero_class))
	var icon: Image = await _render(EnumClass.name(EnumClass.KNIGHT).to_lower(), ICON_SIZE)
	_save(icon, ICON)


func _save(image: Image, path: String) -> void:
	expect(image.save_png(ProjectSettings.globalize_path(path)) == OK, "saved " + path)
	step(path)


func _render(hero_name: String, size: int) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size, size)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.7)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.68)
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-35, 30, 0)
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.6, 0.7, 1.0)
	rim.light_energy = 0.8
	rim.rotation_degrees = Vector3(-20, 200, 0)
	viewport.add_child(rim)
	var camera := Camera3D.new()
	camera.fov = FOV
	viewport.add_child(camera)
	camera.look_at_from_position(EYE, TARGET)
	var hero: CharacterRig = (load(HEROES % hero_name) as PackedScene).instantiate()
	viewport.add_child(hero)
	hero.pose(Clips.IDLE, POSE_S)
	for i: int in 4:
		await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	return image
