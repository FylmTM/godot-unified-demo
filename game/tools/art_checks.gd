class_name ArtChecks
extends RefCounted
## The rules docs/ART.md sets for the game's art, checked: the godot suite's validate step runs them
## (game/tools/validate.gd), so a pack file nobody uses, a mesh that lost its pack's material, a character missing a
## bone or a clip, a kit part whose collision the sim couldn't use, or a stage whose floor doesn't walk in one piece
## fails the suite instead of the look.
##
## Each problem is reported through the validate run's log capture, named by the file it is in. The characters and the
## look-dev scene are run, not only loaded: every clip is posed on every character, and every shot is shown.

## The collision categories a kit part's `unified_category` may hold (the level exporter writes them into the sim's
## filters): the floor, walls (block walking, sight and shots), and low cover (blocks walking only).
const CATEGORY_FLOOR: int = 1
const CATEGORY_WALL: int = 2
const CATEGORY_LOW: int = 4
## Low cover is what can be shot over: no taller than this, in metres; a wall is taller.
const LOW_COVER_HEIGHT: float = 1.5

## How far a part's collision may reach past its model's bounds, in metres: a shape is a simplified box, never bigger
## than what the player sees (the margin is the meshes' rounding).
const SHAPE_TOLERANCE: float = 0.02

const ASSETS: String = "res://assets/"
const GAME: String = "res://game/"
const MATERIALS: String = "res://game/materials/"
const CHARACTERS: Array[String] = ["res://game/characters/heroes/", "res://game/characters/skeletons/"]
const PARTS: String = "res://game/levels/parts/"
const ANIMATIONS: String = "res://game/characters/rig_animations.tscn"
const LOOKDEV: String = "res://game/lookdev/lookdev.tscn"
## The stages a game camera walks: each has one walkable floor.
const STAGES: Array[String] = ["res://game/lookdev/crypt_stage.tscn", "res://game/lookdev/hub_stage.tscn"]
## The stage that places every kit part, so the level exporter sees each one.
const KIT_STAGE: String = "res://game/lookdev/kit_stage.tscn"

## How many problems the checks found.
var problems: int = 0

var _log: UnifiedLogCapture
var _tree_root: Node


## Checks report to `log_capture`; `tree_root` is where a character or the look-dev scene runs while it is checked.
func _init(log_capture: UnifiedLogCapture, tree_root: Node) -> void:
	_log = log_capture
	_tree_root = tree_root


## Runs every check.
func run() -> void:
	_check_assets()
	_check_materials()
	_check_characters()
	_check_clips()
	_check_parts()
	_check_stages()
	_check_lookdev()


## Every pack folder (`assets/<vendor>/<pack>/`) has its licence and a CREDITS.md row; every file in it is a pack's
## glTF, glTF buffer or PNG, or Godot's .import beside one, and something in the game uses it.
func _check_assets() -> void:
	var credits: String = FileAccess.get_file_as_string("res://CREDITS.md")
	var used: Dictionary[String, bool] = _used_files()
	for vendor: String in DirAccess.get_directories_at(ASSETS):
		for stray: String in DirAccess.get_files_at(ASSETS + vendor):
			_problem("a file outside any pack folder", ASSETS + vendor + "/" + stray)
		for pack: String in DirAccess.get_directories_at(ASSETS + vendor):
			var dir: String = "%s%s/%s/" % [ASSETS, vendor, pack]
			if not DirAccess.get_directories_at(dir).is_empty():
				_problem("a pack folder holds folders: a pack's files are flat", dir)
			if not FileAccess.file_exists(dir + "LICENSE.txt"):
				_problem("the pack has no LICENSE.txt", dir)
			if not credits.contains("`assets/%s/%s/`" % [vendor, pack]):
				_problem("the pack has no row in CREDITS.md", dir)
			for file: String in DirAccess.get_files_at(dir):
				_check_asset(dir + file, used)


func _check_asset(path: String, used: Dictionary[String, bool]) -> void:
	match path.get_extension():
		"txt":
			if path.get_file() != "LICENSE.txt":
				_problem("a text file that isn't the pack's LICENSE.txt", path)
		"import":
			if not FileAccess.file_exists(path.get_basename()):
				_problem("an .import whose asset is gone", path)
			else:
				_check_import(path)
		"glb", "gltf", "png":
			if not used.has(path):
				_problem("no scene of the game uses it (only used files are committed)", path)
			if path.get_extension() == "gltf" and not FileAccess.file_exists(path.get_basename() + ".bin"):
				_problem("a .gltf with no .bin", path)
		"bin":
			if not FileAccess.file_exists(path.get_basename() + ".gltf"):
				_problem("a .bin with no .gltf", path)
		_:
			_problem("not a file the art pipeline takes (glTF, its .bin, or PNG)", path)


## An asset's import settings are the pipeline's (docs/ART.md, Import): a texture stays lossless, without mipmaps,
## never switched to VRAM compression; a model builds no tangents, and every material it maps to exists.
func _check_import(path: String) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		_problem("an .import Godot can't read", path)
		return
	match config.get_value("remap", "importer", ""):
		"texture":
			for setting: Array in [["compress/mode", 0], ["mipmaps/generate", false], ["detect_3d/compress_to", 0]]:
				var key: String = setting[0]
				if config.get_value("params", key, null) != setting[1]:
					_problem("%s is %s, not %s" % [key, config.get_value("params", key, null), setting[1]], path)
		"scene":
			if config.get_value("params", "meshes/ensure_tangents", true) != false:
				_problem("the model builds tangents, which nothing uses", path)
			var subresources: Dictionary = config.get_value("params", "_subresources", {})
			var materials: Dictionary = subresources.get("materials", {})
			for material: String in materials:
				var mapping: Dictionary = materials[material]
				var target: String = mapping.get("use_external/path", "")
				if target != "" and not ResourceLoader.exists(target):
					_problem("material %s maps to %s, which doesn't exist" % [material, target], path)


## Every mesh the game shows draws with its own pack's shared material: one in game/materials/ whose texture (when it
## has one) is the pack's, in the same folder as the model. The import maps each pack's material there by name, so a
## mesh that draws with anything else went around the pipeline, or met another pack's material of the same name.
func _check_materials() -> void:
	var scenes: Array[String] = [LOOKDEV, KIT_STAGE]
	for dir: String in CHARACTERS:
		scenes.append_array(_files(dir, "tscn"))
	scenes.append_array(_files("res://game/levels/", "tscn"))  # the game's level scenes (their parts are in the kit stage)
	for path: String in scenes:
		var node: Node = (load(path) as PackedScene).instantiate()
		for found: Node in node.find_children("*", "MeshInstance3D", true, false):
			_check_mesh(found as MeshInstance3D, node, path)
		node.free()


func _check_mesh(mesh_node: MeshInstance3D, scene_root: Node, path: String) -> void:
	var model: String = mesh_node.owner.scene_file_path if mesh_node.owner else ""
	for surface: int in mesh_node.mesh.get_surface_count():
		var material: Material = mesh_node.get_active_material(surface)
		var where: String = String(scene_root.get_path_to(mesh_node))
		if material == null or not material.resource_path.begins_with(MATERIALS):
			_problem("%s draws with %s, not a shared material" % [
				where, material.resource_path if material else "nothing"], path)
			return
		var texture: Texture2D = (material as BaseMaterial3D).albedo_texture if material is BaseMaterial3D else null
		if texture != null and texture.resource_path.get_base_dir() != model.get_base_dir():
			_problem("%s (from %s) draws with %s, another pack's atlas" % [where, model, material.resource_path], path)
			return


## Every character scene is a CharacterRig on KayKit's Rig_Medium: its bones by name, its hands bound to the hand
## slots of its own skeleton, and the shared animation player in manual mode; and every clip poses on it.
func _check_characters() -> void:
	for dir: String in CHARACTERS:
		for path: String in _files(dir, "tscn"):
			var node: Node = (load(path) as PackedScene).instantiate()
			if not node is CharacterRig:
				_problem("the root is not a CharacterRig", path)
				node.free()
				continue
			var rig: CharacterRig = node
			_check_skeleton(rig, path)
			var player: AnimationPlayer = rig.get_node_or_null("AnimationPlayer")
			if player == null or player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
				_problem("no AnimationPlayer in manual mode (CharacterRig.pose sets every frame)", path)
			else:
				_check_poses(rig, player, path)
			if dir.ends_with("heroes/"):
				_check_two_sided(rig, path)
			rig.free()


## Every clip poses on the character, at the time pose() promises: a looping clip wraps, a one-shot holds its end.
func _check_poses(rig: CharacterRig, player: AnimationPlayer, path: String) -> void:
	_tree_root.add_child(rig)
	for clip: StringName in _clips():
		if not player.has_animation(clip):
			continue
		var length: float = player.get_animation(clip).length
		var past_end: float = length + 0.25
		rig.pose(clip, past_end)
		var expected: float = fposmod(past_end, length) if clip in Clips.LOOPING else length
		if not is_equal_approx(player.current_animation_position, expected):
			_problem("pose(%s, %.2f) shows %.2f s, not %.2f" % [
				clip, past_end, player.current_animation_position, expected], path)
	_tree_root.remove_child(rig)


## A hero's materials draw both sides of a face: capes and cloaks are single sheets, seen from behind as much as from
## the front.
func _check_two_sided(rig: CharacterRig, path: String) -> void:
	for found: Node in rig.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = found
		var material: BaseMaterial3D = mesh_node.get_active_material(0) as BaseMaterial3D
		if material != null and material.cull_mode != BaseMaterial3D.CULL_DISABLED:
			_problem("%s culls back faces: a hero's cape shows from behind" % material.resource_path, path)
			return


func _check_skeleton(rig: CharacterRig, path: String) -> void:
	var skeleton: Skeleton3D = rig.get_node_or_null("Model/Rig_Medium/Skeleton3D")
	if skeleton == null:
		_problem("no Model/Rig_Medium/Skeleton3D", path)
		return
	var bones: PackedStringArray = []
	for bone: int in skeleton.get_bone_count():
		bones.append(skeleton.get_bone_name(bone))
	bones.sort()
	var wanted: PackedStringArray = CharacterRig.BONES.duplicate()
	wanted.sort()
	if bones != wanted:
		_problem("its bones are not Rig_Medium's: %s" % ", ".join(bones), path)
	if rig.get_node_or_null("HandR") == null:
		_problem("no HandR: every character holds something", path)
	for hand: String in ["HandR", "HandL"]:
		var attachment: BoneAttachment3D = rig.get_node_or_null(hand)
		if attachment == null:
			continue
		var bone_name: String = "handslot.r" if hand == "HandR" else "handslot.l"
		if attachment.bone_name != bone_name:
			_problem("%s is bound to %s, not %s" % [hand, attachment.bone_name, bone_name], path)
		if attachment.get_node_or_null(attachment.external_skeleton) != skeleton:
			_problem("%s follows %s, not the model's skeleton" % [hand, attachment.external_skeleton], path)


## Every clip the game names (each StringName constant of Clips) exists and animates only Rig_Medium bones, so it plays
## on every character; Clips.LOOPING names only those clips.
func _check_clips() -> void:
	var player: AnimationPlayer = (load(ANIMATIONS) as PackedScene).instantiate()
	var clips: Array[StringName] = _clips()
	for clip: StringName in Clips.LOOPING:
		if clip not in clips:
			_problem("Clips.LOOPING names %s, which no constant of Clips does" % clip, ANIMATIONS)
		elif player.has_animation(clip) and not _seamless(player.get_animation(clip)):
			_problem("Clips.LOOPING names %s, which ends in another pose than it starts: it can't loop" % clip, ANIMATIONS)
	for clip: StringName in clips:
		if not player.has_animation(clip):
			_problem("no clip %s" % clip, ANIMATIONS)
			continue
		var animation: Animation = player.get_animation(clip)
		for track: int in animation.get_track_count():
			var track_path: NodePath = animation.track_get_path(track)
			var bone: String = String(track_path.get_concatenated_subnames())
			if String(track_path.get_concatenated_names()) != "Rig_Medium/Skeleton3D" or bone not in CharacterRig.BONES:
				_problem("%s animates %s, not a Rig_Medium bone" % [clip, track_path], ANIMATIONS)
				break
	player.free()


## Every kit part (a scene at `parts/<kit>/`) is either collidable (a StaticBody3D with a category its height allows,
## box or cylinder shapes inside the model, a floor exactly one box whose top is y = 0 under the model's whole
## footprint) or decor (no body at all); and the kit stage places it exactly once, so the level exporter sees it.
func _check_parts() -> void:
	var placed: Dictionary[String, int] = _instances(KIT_STAGE)
	var found: Array[String] = []
	_collect_scenes(PARTS, found)
	for path: String in found:
		if path.get_base_dir().get_base_dir() + "/" != PARTS:
			_problem("a part outside a kit folder (parts/<kit>/): the part rules can't place it", path)
			continue
		if placed.get(path, 0) != 1:
			_problem("the kit stage places it %d times, not once" % placed.get(path, 0), path)
		var node: Node3D = (load(path) as PackedScene).instantiate()
		if node is StaticBody3D:
			_check_body(node as StaticBody3D, path)
		elif node is CollisionObject3D or not node.find_children("*", "CollisionObject3D", true, false).is_empty():
			_problem("a decor part with a body: a collidable part's root is its StaticBody3D, with no body under it", path)
		node.free()


func _check_body(body: StaticBody3D, path: String) -> void:
	var category: int = body.get_meta(&"unified_category", 0)
	var bounds: AABB = _mesh_bounds(body)
	if not body.find_children("*", "CollisionObject3D", true, false).is_empty():
		_problem("a body under the part's StaticBody3D: the exporter reads only the root's shapes", path)
	var shapes: Array[CollisionShape3D] = []
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			shapes.append(child as CollisionShape3D)
		elif child is CollisionPolygon3D:
			_problem("%s: the exporter reads boxes and cylinders, not polygons" % child.name, path)
	if shapes.is_empty():
		_problem("a StaticBody3D with no collision shape", path)
		return
	var top: float = -INF
	for collision: CollisionShape3D in shapes:
		var extent: AABB = _shape_bounds(collision)
		if not extent.has_volume():
			_problem("%s is not a box or a cylinder" % collision.name, path)
			continue
		top = maxf(top, extent.end.y)
		if category != CATEGORY_FLOOR and not bounds.grow(SHAPE_TOLERANCE).encloses(extent):
			_problem("%s reaches past the model (%s outside %s)" % [collision.name, extent, bounds], path)
	match category:
		CATEGORY_FLOOR:
			_check_floor(shapes, bounds, path)
		CATEGORY_LOW:
			if bounds.end.y > LOW_COVER_HEIGHT + SHAPE_TOLERANCE:
				_problem("low cover %.2f m tall: anything over %.1f m is a wall" % [bounds.end.y, LOW_COVER_HEIGHT], path)
		CATEGORY_WALL:
			if top <= LOW_COVER_HEIGHT:
				_problem("a wall %.2f m tall: anything up to %.1f m is low cover" % [top, LOW_COVER_HEIGHT], path)
		_:
			_problem("unified_category %d is none of the game's (floor, wall, low)" % category, path)


## A floor is one unrotated box (a slab under the walking surface, reaching below the model, which is only a few
## centimetres thick), its top at y = 0 and its footprint the model's.
func _check_floor(shapes: Array[CollisionShape3D], bounds: AABB, path: String) -> void:
	var slab: CollisionShape3D = shapes[0]
	if shapes.size() != 1 or not slab.shape is BoxShape3D or not slab.transform.basis.is_equal_approx(Basis.IDENTITY):
		_problem("a floor is one unrotated box", path)
		return
	var extent: AABB = _shape_bounds(slab)
	if not is_zero_approx(extent.end.y):
		_problem("the floor's top is at y = %.3f, not 0" % extent.end.y, path)
	if not _same_footprint(extent, bounds):
		_problem("the floor's shape covers %s, its model %s" % [extent, bounds], path)


## Each stage is built as a level should be: a placed part is a plain instance (it overrides neither its category nor
## its script, which the part's scene owns) and never scaled, and in a camera's stage a floor or a wall sits on the
## 2 m grid, turned in 90° steps. A camera's stage walks in one piece: its baked navigation mesh (`uni bake --nav`) has exactly one island
## on the floor (the tops of walls and furniture bake into islands of their own, which nothing reaches).
func _check_stages() -> void:
	for path: String in STAGES + [KIT_STAGE]:
		var state: SceneState = (load(path) as PackedScene).get_state()
		for node: int in state.get_node_count():
			_check_placed(state, node, path, path != KIT_STAGE)
	for path: String in STAGES:
		var node: Node = (load(path) as PackedScene).instantiate()
		var region: NavigationRegion3D = node.get_node_or_null("Nav")
		if region == null or region.navigation_mesh == null:
			_problem("no navigation region Nav", path)
		else:
			var islands: int = _floor_islands(region.navigation_mesh)
			if islands != 1:
				_problem("the floor walks in %d pieces, not one: a gap narrower than an agent cuts it" % islands, path)
		node.free()


## One placed node of a stage's: a plain instance, never scaled, and on the grid when `gridded` (a level, not the kit
## stage's gallery).
func _check_placed(state: SceneState, node: int, path: String, gridded: bool) -> void:
	var instance: PackedScene = state.get_node_instance(node)
	if instance == null:
		return
	var where: String = String(state.get_node_path(node))
	var placement: Transform3D = Transform3D.IDENTITY
	for property: int in state.get_node_property_count(node):
		match state.get_node_property_name(node, property):
			&"metadata/unified_category":
				_problem("%s overrides its part's category" % where, path)
			&"script":
				_problem("%s overrides its scene's script" % where, path)
			&"transform":
				placement = state.get_node_property_value(node, property)
	var part: String = instance.resource_path
	if not part.begins_with(PARTS):
		return
	if not placement.basis.get_scale().is_equal_approx(Vector3.ONE):
		_problem("%s is scaled: a part is placed at its own size" % where, path)
	var piece: String = part.get_file()
	if not gridded or not (piece.begins_with("floor") or piece.begins_with("wall")):
		return
	var yaw: float = rad_to_deg(placement.basis.get_euler().y)
	# a wall's origin is on a grid line; a floor's footprint edges are (a 2 m tile is centred on an odd metre)
	var corner: Vector3 = placement.origin
	if piece.begins_with("floor"):
		var part_node: Node3D = instance.instantiate()
		corner = (placement * _mesh_bounds(part_node)).position
		part_node.free()
	var on_grid: bool = _on_grid(corner.x) and _on_grid(corner.z)
	if not on_grid or not is_zero_approx(fposmod(roundf(yaw), 90.0)) or absf(yaw - roundf(yaw)) > 0.01:
		_problem("%s is off the grid: floors and walls sit on 2 m steps, turned by 90°" % where, path)


## The look-dev scene runs: every shot shows, and every cast member poses, each pose naming a member that exists.
func _check_lookdev() -> void:
	var lookdev: Lookdev = (load(LOOKDEV) as PackedScene).instantiate()
	_tree_root.add_child(lookdev)
	for index: int in lookdev.shots.size():
		lookdev.show_shot(index)
	lookdev.pose_cast(0.5)
	for member: StringName in lookdev.poses:
		if lookdev.get_node_or_null(NodePath("Cast/" + String(member))) == null:
			_problem("a pose for %s, whom the cast doesn't have" % member, LOOKDEV)
	_tree_root.remove_child(lookdev)
	lookdev.free()


## How many times a scene instances each scene, by path.
func _instances(path: String) -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	var state: SceneState = (load(path) as PackedScene).get_state()
	for node: int in state.get_node_count():
		var instance: PackedScene = state.get_node_instance(node)
		if instance != null:
			counts[instance.resource_path] = counts.get(instance.resource_path, 0) + 1
	return counts


## Whether a clip ends in the pose it starts with, on every track: what a loop needs to wrap without a jump.
func _seamless(animation: Animation) -> bool:
	for track: int in animation.get_track_count():
		var keys: int = animation.track_get_key_count(track)
		if keys < 2:
			continue
		var first: Variant = animation.track_get_key_value(track, 0)
		var last: Variant = animation.track_get_key_value(track, keys - 1)
		if first is Quaternion:
			var a: Quaternion = first
			var b: Quaternion = last
			if absf(a.dot(b)) < 0.999:
				return false
		elif first is Vector3:
			var a: Vector3 = first
			var b: Vector3 = last
			if a.distance_to(b) > 0.01:
				return false
	return true


## The clips the game names: every StringName constant of Clips.
func _clips() -> Array[StringName]:
	var out: Array[StringName] = []
	var constants: Dictionary = (Clips as Script).get_script_constant_map()
	for value: Variant in constants.values():
		if value is StringName:
			var clip: StringName = value
			out.append(clip)
	return out


## How many islands the polygons at floor height make, joined where they share a vertex. Godot's bake floats the mesh
## a little above what it walks (the exporter lowers it), so the floor is the lowest vertex, and a polygon is on it when
## every vertex is within half a metre of it: the top of anything taller is not.
func _floor_islands(mesh: NavigationMesh) -> int:
	var vertices: PackedVector3Array = mesh.get_vertices()
	var floor_y: float = INF
	for vertex: Vector3 in vertices:
		floor_y = minf(floor_y, vertex.y)
	var parent: Dictionary[int, int] = {}
	var owner_of: Dictionary[int, int] = {}
	for polygon: int in mesh.get_polygon_count():
		var indices: PackedInt32Array = mesh.get_polygon(polygon)
		var on_floor: bool = true
		for v: int in indices:
			on_floor = on_floor and vertices[v].y < floor_y + 0.5
		if not on_floor:
			continue
		parent[polygon] = polygon
		for v: int in indices:
			if owner_of.has(v):
				parent[_find(parent, polygon)] = _find(parent, owner_of[v])
			else:
				owner_of[v] = polygon
	var roots: Dictionary[int, bool] = {}
	for polygon: int in parent:
		roots[_find(parent, polygon)] = true
	return roots.size()


func _find(parent: Dictionary[int, int], polygon: int) -> int:
	while parent[polygon] != polygon:
		polygon = parent[polygon]
	return polygon


## Every file a scene under game/ depends on, recursively (a glTF's texture through the shared material its import
## maps it to).
func _used_files() -> Dictionary[String, bool]:
	var used: Dictionary[String, bool] = {}
	var pending: Array[String] = []
	_collect_scenes(GAME, pending)
	while not pending.is_empty():
		var path: String = pending.pop_back()
		if used.has(path):
			continue
		used[path] = true
		for dependency: String in _dependencies(path):
			if not used.has(dependency):
				pending.append(dependency)
	return used


## The paths a resource depends on directly, uids resolved.
func _dependencies(path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for dependency: String in ResourceLoader.get_dependencies(path):
		var dependency_path: String = dependency.get_slice("::", dependency.get_slice_count("::") - 1)
		if dependency_path.begins_with("uid://"):
			dependency_path = ResourceUID.uid_to_path(dependency_path)
		out.append(dependency_path)
	return out


func _collect_scenes(dir: String, out: Array[String]) -> void:
	out.append_array(_files(dir, "tscn"))
	for sub: String in DirAccess.get_directories_at(dir):
		_collect_scenes(dir + sub + "/", out)


func _shape_bounds(collision: CollisionShape3D) -> AABB:
	var local: AABB = AABB()
	if collision.shape is BoxShape3D:
		var size: Vector3 = (collision.shape as BoxShape3D).size
		local = AABB(-size / 2, size)
	elif collision.shape is CylinderShape3D:
		var cylinder: CylinderShape3D = collision.shape
		var size: Vector3 = Vector3(cylinder.radius * 2, cylinder.height, cylinder.radius * 2)
		local = AABB(-size / 2, size)
	return collision.transform * local


func _mesh_bounds(root_node: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var first: bool = true
	for found: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = found
		var xform: Transform3D = Transform3D.IDENTITY
		var current: Node = mesh_node
		while current != root_node:
			xform = (current as Node3D).transform * xform
			current = current.get_parent()
		var box: AABB = xform * mesh_node.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


## Whether `x` is on the kit's 2 m grid, to the meshes' rounding.
func _on_grid(x: float) -> bool:
	var off: float = fposmod(x, 2.0)
	return off < SHAPE_TOLERANCE or off > 2.0 - SHAPE_TOLERANCE


func _same_footprint(a: AABB, b: AABB) -> bool:
	return (
		absf(a.position.x - b.position.x) <= SHAPE_TOLERANCE and absf(a.end.x - b.end.x) <= SHAPE_TOLERANCE
		and absf(a.position.z - b.position.z) <= SHAPE_TOLERANCE and absf(a.end.z - b.end.z) <= SHAPE_TOLERANCE
	)


func _files(dir: String, extension: String) -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == extension:
			out.append(dir + file)
	return out


func _problem(message: String, at: String) -> void:
	problems += 1
	_log.add(message, at)
