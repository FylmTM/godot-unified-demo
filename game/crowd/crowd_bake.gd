class_name CrowdBake
extends RefCounted
## Bakes a character for a crowd drawn as one MultiMesh: its meshes and weapons merged into one lighter surface that
## keeps its skin, and its clips baked as bone matrices into a texture (CrowdClips) that the crowd's shader skins the
## surface from, so a crowd is one draw call and its animation costs no node. What to bake is a Recipe (the game's:
## game/crowd/minion_crowd.gd); `./uni tool bake_crowd` writes it; the art checks prove it fresh, and that it poses
## as the character scene does.
##
## A character is a node with one Skeleton3D: meshes skinned to it, weapons on BoneAttachment3Ds, and a way to pose it
## (a Callable taking a clip and the seconds into it). A bone's matrix is the one Godot skins by, the bone's pose in the
## character's space times its skin's bind (every mesh's skin must bind a bone alike), so the baked pose is the scene's
## own. A weapon is bound to its hand's bone with weight 1, through that bone's bind, so it needs no bone of its own. A
## hidden mesh is left out: the scene doesn't draw it either.
##
## Nothing here knows the game: it moves into unified's tools_godot once the crowd is drawn with it.

## Weights kept per vertex: a crowd's shader skins with four.
const WEIGHTS: int = 4
## The angles generate_lods takes (degrees): normals closer than the first merge, farther than the second split. The
## scene importer's defaults, so the chain is the one Godot makes for the model's own LODs.
const LOD_MERGE_ANGLE: float = 25.0
const LOD_SPLIT_ANGLE: float = 60.0


## Bakes `rig` (in the tree: its poses are computed), posed by `pose` (clip, seconds), as `recipe` says: its meshes
## merged, each lightened, its clips baked.
static func bake(rig: Node3D, pose: Callable, recipe: Recipe) -> Baked:
	var lightened: Lightened = lighten(merge(rig, recipe.glow), recipe.max_error)
	var baked := Baked.new()
	baked.clips = bake_clips(rig, pose, recipe, lightened.arrays)
	baked.mesh = ArrayMesh.new()
	baked.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lightened.arrays, [], {}, format())
	baked.mesh.custom_aabb = baked.clips.bounds
	return baked


## The surface format a crowd mesh is made with: its bones' indices in CUSTOM0 and their weights in CUSTOM1, as floats
## (a skinned mesh's own bone arrays reach no shader without a skeleton).
static func format() -> int:
	return (
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	)


## The skeleton `rig`'s skinned meshes are bound to (each mesh's own skeleton path; they must share one).
static func skeleton_of(rig: Node3D) -> Skeleton3D:
	var skeleton: Skeleton3D = null
	for mesh_node: MeshInstance3D in meshes_of(rig):
		if mesh_node.skin == null:
			continue
		var bound: Skeleton3D = mesh_node.get_node_or_null(mesh_node.skeleton) as Skeleton3D
		assert(bound != null, "%s: skinned to no Skeleton3D" % mesh_node.name)
		assert(skeleton == null or bound == skeleton, "%s: skinned to another skeleton" % mesh_node.name)
		skeleton = bound
	assert(skeleton != null, "no skinned mesh")
	return skeleton


## The meshes the bake merges: every visible MeshInstance3D under `rig`, in tree order.
static func meshes_of(rig: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for found: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = found
		if mesh_node.is_visible_in_tree():
			out.append(mesh_node)
	return out


## `node`'s transform in `space`'s, from their global transforms (both in the tree).
static func relative(space: Node3D, node: Node3D) -> Transform3D:
	return space.global_transform.affine_inverse() * node.global_transform


## Each bone's bind (its skins' inverse rest, mesh space to bone space). Every skin must bind a bone alike: one matrix
## a bone skins every mesh with. A bone no skin binds gets the inverse of its rest.
static func binds(rig: Node3D) -> Array[Transform3D]:
	var skeleton: Skeleton3D = skeleton_of(rig)
	var out: Array[Transform3D] = []
	var bound: Array[bool] = []
	for bone: int in skeleton.get_bone_count():
		out.append(skeleton.get_bone_global_rest(bone).affine_inverse())
		bound.append(false)
	for mesh_node: MeshInstance3D in meshes_of(rig):
		var skin: Skin = mesh_node.skin
		if skin == null:
			continue
		for bind: int in skin.get_bind_count():
			var bone: int = bind_bone(skeleton, skin, bind)
			var pose: Transform3D = skin.get_bind_pose(bind)
			assert(not bound[bone] or out[bone].is_equal_approx(pose), "two skins bind %s apart" % skeleton.get_bone_name(bone))
			out[bone] = pose
			bound[bone] = true
	return out


## Each bone's skinning matrix in `rig`'s space as it is posed now: what a vertex bound to it is moved by.
static func skinning(rig: Node3D, skeleton: Skeleton3D, bind_poses: Array[Transform3D]) -> Array[Transform3D]:
	var to_rig: Transform3D = relative(rig, skeleton)
	var out: Array[Transform3D] = []
	for bone: int in skeleton.get_bone_count():
		out.append(to_rig * skeleton.get_bone_global_pose(bone) * bind_poses[bone])
	return out


## The skeleton bone a skin's bind binds (by name, else by index).
static func bind_bone(skeleton: Skeleton3D, skin: Skin, bind: int) -> int:
	var bind_name: StringName = skin.get_bind_name(bind)
	var bone: int = skeleton.find_bone(bind_name) if bind_name != &"" else skin.get_bind_bone(bind)
	assert(bone >= 0, "a bind to no bone of the skeleton: %s" % bind_name)
	return bone


## Every mesh of `rig` (meshes_of) merged into one surface's arrays, in its skeleton's bind space: positions, normals,
## UVs, the glow mask in UV2's x (1 on a mesh drawn with `glow`, else 0: not the vertex colour, which an instance's
## colour would multiply), the bones (skeleton indices) in CUSTOM0 and their weights in CUSTOM1, four each (a vertex's
## strongest, summing to 1). A weapon (a mesh on a BoneAttachment3D) is bound to its bone with weight 1, placed through
## that bone's bind where the attachment holds it.
static func merge(rig: Node3D, glow: Material) -> Merged:
	var merged := Merged.new()
	var skeleton: Skeleton3D = skeleton_of(rig)
	var bind_poses: Array[Transform3D] = binds(rig)
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var masks := PackedVector2Array()
	var bones := PackedFloat32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for mesh_node: MeshInstance3D in meshes_of(rig):
		assert(mesh_node.mesh.get_surface_count() == 1, "%s: one surface a mesh" % mesh_node.name)
		var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
		var source_positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var source_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material: Material = mesh_node.get_active_material(0)
		var glowing: bool = material != null and material.resource_path == glow.resource_path
		var base: int = positions.size()
		var place: Transform3D = Transform3D.IDENTITY
		var bone_map: PackedInt32Array = []
		var source_bones := PackedInt32Array()
		var source_weights := PackedFloat32Array()
		var per_vertex: int = 0
		if mesh_node.skin != null:
			var at_skeleton: bool = relative(skeleton, mesh_node).is_equal_approx(Transform3D.IDENTITY)
			assert(at_skeleton, "%s: a skinned mesh sits at its skeleton" % mesh_node.name)
			for bind: int in mesh_node.skin.get_bind_count():
				bone_map.append(bind_bone(skeleton, mesh_node.skin, bind))
			source_bones = arrays[Mesh.ARRAY_BONES]
			source_weights = arrays[Mesh.ARRAY_WEIGHTS]
			per_vertex = roundi(float(source_bones.size()) / source_positions.size())
		else:
			var attachment: BoneAttachment3D = _attachment_of(mesh_node, rig)
			assert(attachment != null, "%s: neither skinned nor held" % mesh_node.name)
			var bone: int = skeleton.find_bone(attachment.bone_name)
			place = bind_poses[bone].affine_inverse() * relative(attachment, mesh_node)
			bone_map.append(bone)
		var turn: Basis = place.basis.inverse().transposed()  # normals turn by the inverse transpose
		for vertex: int in source_positions.size():
			positions.append(place * source_positions[vertex])
			normals.append((turn * source_normals[vertex]).normalized())
			uvs.append(source_uvs[vertex])
			masks.append(Vector2(1.0 if glowing else 0.0, 0.0))
			if per_vertex == 0:
				bones.append_array(PackedFloat32Array([bone_map[0], 0, 0, 0]))
				weights.append_array(PackedFloat32Array([1, 0, 0, 0]))
				continue
			var strongest: Array[Vector2] = []  # (weight, bone)
			for k: int in per_vertex:
				var weight: float = source_weights[vertex * per_vertex + k]
				strongest.append(Vector2(weight, bone_map[source_bones[vertex * per_vertex + k]]))
			strongest.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
			var total: float = 0.0
			for k: int in WEIGHTS:
				total += strongest[k].x
			for k: int in WEIGHTS:
				bones.append(strongest[k].y if strongest[k].x > 0 else 0.0)
				weights.append(strongest[k].x / total)
		var part := PackedInt32Array()
		for index: int in source_indices:
			part.append(base + index)
		merged.parts.append(part)
		merged.glowing.append(glowing)
		merged.meshes.append(mesh_node)
		merged.bases.append(base)
		indices.append_array(part)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = positions
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_TEX_UV2] = masks
	out[Mesh.ARRAY_CUSTOM0] = bones
	out[Mesh.ARRAY_CUSTOM1] = weights
	out[Mesh.ARRAY_INDEX] = indices
	merged.arrays = out
	return merged


## A merged character lightened: each of its meshes at the coarsest of Godot's own LODs for it whose error is within
## `max_error` (ImporterMesh.generate_lods, the scene importer's: meshoptimizer, which moves no vertex and keeps the
## normals' and UVs' seams, so the palette atlas stays exact; its error is relative to the mesh's size), the vertices
## no triangle uses dropped. Mesh by mesh, not the merged surface whole: on the whole one the chain halves it at each
## step, and its second step already drops the eyes (a small part collapses first). A glowing mesh stays whole: the
## eyes are what a crowd reads by.
static func lighten(merged: Merged, max_error: float) -> Lightened:
	var arrays: Array = merged.arrays
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var kept := PackedInt32Array()
	for index: int in merged.parts.size():
		var part: PackedInt32Array = merged.parts[index]
		if merged.glowing[index]:
			kept.append_array(part)
			continue
		var local: Array[PackedInt32Array] = _compact(part)  # the part alone: its LOD errors are relative to its size
		var shape: Array = []
		shape.resize(Mesh.ARRAY_MAX)
		var part_positions := PackedVector3Array()
		var part_normals := PackedVector3Array()
		var part_uvs := PackedVector2Array()
		for vertex: int in local[0]:
			part_positions.append(positions[vertex])
			part_normals.append(normals[vertex])
			part_uvs.append(uvs[vertex])
		shape[Mesh.ARRAY_VERTEX] = part_positions
		shape[Mesh.ARRAY_NORMAL] = part_normals
		shape[Mesh.ARRAY_TEX_UV] = part_uvs
		shape[Mesh.ARRAY_INDEX] = local[1]
		var chain := ImporterMesh.new()
		chain.add_surface(Mesh.PRIMITIVE_TRIANGLES, shape)
		chain.generate_lods(LOD_MERGE_ANGLE, LOD_SPLIT_ANGLE, [])
		var lightest: PackedInt32Array = local[1]
		for lod: int in chain.get_surface_lod_count(0):
			if chain.get_surface_lod_size(0, lod) > max_error:
				break
			lightest = chain.get_surface_lod_indices(0, lod)
		for local_index: int in lightest:
			kept.append(local[0][local_index])
	var compacted: Array[PackedInt32Array] = _compact(kept)
	var lightened := Lightened.new()
	lightened.source = compacted[0]
	lightened.arrays.resize(Mesh.ARRAY_MAX)
	var masks: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var bones: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	var new_positions := PackedVector3Array()
	var new_normals := PackedVector3Array()
	var new_uvs := PackedVector2Array()
	var new_masks := PackedVector2Array()
	var new_bones := PackedFloat32Array()
	var new_weights := PackedFloat32Array()
	for old: int in lightened.source:
		new_positions.append(positions[old])
		new_normals.append(normals[old])
		new_uvs.append(uvs[old])
		new_masks.append(masks[old])
		new_bones.append_array(bones.slice(old * WEIGHTS, old * WEIGHTS + WEIGHTS))
		new_weights.append_array(weights.slice(old * WEIGHTS, old * WEIGHTS + WEIGHTS))
	lightened.arrays[Mesh.ARRAY_VERTEX] = new_positions
	lightened.arrays[Mesh.ARRAY_NORMAL] = new_normals
	lightened.arrays[Mesh.ARRAY_TEX_UV] = new_uvs
	lightened.arrays[Mesh.ARRAY_TEX_UV2] = new_masks
	lightened.arrays[Mesh.ARRAY_CUSTOM0] = new_bones
	lightened.arrays[Mesh.ARRAY_CUSTOM1] = new_weights
	lightened.arrays[Mesh.ARRAY_INDEX] = compacted[1]
	return lightened


## The recipe's clips baked from `rig`, posed by `pose` (clip, seconds) as the scene shows them, each at its rate (a
## clip's length must be a whole number of its frames: the bake fails otherwise), with the bounds every pose sweeps
## `arrays` (the crowd's surface) through and each clip's last pose's top.
static func bake_clips(rig: Node3D, pose: Callable, recipe: Recipe, arrays: Array) -> CrowdClips:
	var player: AnimationPlayer = rig.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = skeleton_of(rig)
	var bind_poses: Array[Transform3D] = binds(rig)
	var bone_count: int = bind_poses.size()
	var clips := CrowdClips.new()
	clips.bone_count = bone_count
	var rows: int = 0
	for index: int in recipe.clips.size():
		var clip: StringName = recipe.clips[index]
		var fps: float = recipe.rates[index]
		var frames: float = player.get_animation(clip).length * fps
		assert(absf(frames - roundf(frames)) < 0.001, "%s: %.3f frames at %d fps, not a whole number" % [clip, frames, fps])
		clips.clips.append(clip)
		clips.first_rows.append(rows)
		clips.frame_counts.append(roundi(frames) + 1)
		clips.rates.append(fps)
		clips.loops.append(clip in recipe.loops)
		rows += roundi(frames) + 1
	clips.bones = Image.create_empty(bone_count * CrowdClips.TEXELS_PER_BONE, rows, false, Image.FORMAT_RGBAF)
	var reach: Dictionary[int, AABB] = bone_reach(arrays, bind_poses)
	var bounds: AABB = AABB()
	var first: bool = true
	for clip: int in clips.clips.size():
		var last: int = clips.frame_counts[clip] - 1
		for frame: int in clips.frame_counts[clip]:
			pose.call(clips.clips[clip], minf(frame / clips.rates[clip], clips.length(clip)))
			var matrices: Array[Transform3D] = skinning(rig, skeleton, bind_poses)
			for bone: int in bone_count:
				var m: Transform3D = matrices[bone]
				for row: int in CrowdClips.TEXELS_PER_BONE:
					var texel := Color(m.basis.x[row], m.basis.y[row], m.basis.z[row], m.origin[row])
					clips.bones.set_pixel(bone * CrowdClips.TEXELS_PER_BONE + row, clips.first_rows[clip] + frame, texel)
				if not reach.has(bone):
					continue  # it moves no vertex
				var box: AABB = m * reach[bone]
				bounds = box if first else bounds.merge(box)
				first = false
			if frame == last:
				clips.tops.append(_top(arrays, matrices))
	clips.bounds = bounds
	return clips


## Per bone that moves a vertex of `arrays` (a crowd surface), the bounds of those vertices in its bone space: a pose's
## matrix for the bone carries them where the bone is, and a skinned vertex lies within the boxes of its bones.
static func bone_reach(arrays: Array, bind_poses: Array[Transform3D]) -> Dictionary[int, AABB]:
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	var out: Dictionary[int, AABB] = {}
	for vertex: int in positions.size():
		for k: int in WEIGHTS:
			if weights[vertex * WEIGHTS + k] <= 0.0:
				continue
			var bone: int = int(bones[vertex * WEIGHTS + k])
			var point: Vector3 = bind_poses[bone] * positions[vertex]
			out[bone] = out[bone].expand(point) if out.has(bone) else AABB(point, Vector3.ZERO)
	return out


## Where vertex `vertex` of `arrays` (a crowd surface) stands, skinned by `matrices` (one per bone): the shader's sum.
static func skin_vertex(arrays: Array, vertex: int, matrices: Array[Transform3D]) -> Vector3:
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	var point := Vector3.ZERO
	for k: int in WEIGHTS:
		var weight: float = weights[vertex * WEIGHTS + k]
		if weight > 0.0:
			point += weight * (matrices[int(bones[vertex * WEIGHTS + k])] * positions[vertex])
	return point


## A hash of what a bake is made from: Godot's version (a new one may import, animate or lighten a model otherwise),
## `recipe` (the bake's parameters, as text) and the bytes of `files` (input_files), so a check can tell a committed
## bake from a stale one.
static func inputs_hash(recipe: Recipe, files: PackedStringArray) -> String:
	var sorted: PackedStringArray = files.duplicate()
	sorted.sort()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	var version: String = Engine.get_version_info()["string"]
	hashing.update(version.to_utf8_buffer())
	hashing.update(recipe.describe().to_utf8_buffer())
	for path: String in sorted:
		hashing.update(path.to_utf8_buffer())
		hashing.update(FileAccess.get_file_as_bytes(path))
	return hashing.finish().hex_encode()


## The files a bake of `scene` reads: the scene, everything it loads (each imported file's source, its .import and a
## glTF's buffer), and this script (the bake's code).
static func input_files(scene: String) -> PackedStringArray:
	var out: PackedStringArray = [(CrowdBake as Script).resource_path]
	var pending: PackedStringArray = [scene]
	while not pending.is_empty():
		var path: String = pending[pending.size() - 1]
		pending.remove_at(pending.size() - 1)
		if path in out:
			continue
		out.append(path)
		for extra: String in [path + ".import", path.get_basename() + ".bin"]:
			if FileAccess.file_exists(extra) and extra not in out:
				out.append(extra)
		for dependency: String in ResourceLoader.get_dependencies(path):
			var dependency_path: String = dependency.get_slice("::", dependency.get_slice_count("::") - 1)
			if dependency_path.begins_with("uid://"):
				dependency_path = ResourceUID.uid_to_path(dependency_path)
			if dependency_path not in out:
				pending.append(dependency_path)
	return out


## The highest point of `arrays` (a crowd surface) skinned by `matrices`.
static func _top(arrays: Array, matrices: Array[Transform3D]) -> float:
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var top: float = -INF
	for vertex: int in positions.size():
		top = maxf(top, skin_vertex(arrays, vertex, matrices).y)
	return top


## The vertices `indices` use, in first-use order, and the indices renumbered to them: [vertices, indices].
static func _compact(indices: PackedInt32Array) -> Array[PackedInt32Array]:
	var numbered: Dictionary[int, int] = {}
	var vertices := PackedInt32Array()
	var renumbered := PackedInt32Array()
	for index: int in indices:
		if not numbered.has(index):
			numbered[index] = vertices.size()
			vertices.append(index)
		renumbered.append(numbered[index])
	return [vertices, renumbered]


## The BoneAttachment3D holding `node` (its nearest such ancestor below `rig`), or null.
static func _attachment_of(node: Node, rig: Node) -> BoneAttachment3D:
	var current: Node = node.get_parent()
	while current != null and current != rig:
		if current is BoneAttachment3D:
			return current
		current = current.get_parent()
	return null


## What a bake makes of a character: which clips, which of them loop, the rate each is baked at, the material its
## glowing meshes are drawn with, and how far each mesh is lightened (lighten).
class Recipe:
	var clips: Array[StringName] = []
	var loops: Array[StringName] = []
	var rates: PackedFloat32Array = []
	var glow: Material
	var max_error: float

	## The recipe as text, for inputs_hash.
	func describe() -> String:
		var looping: Array[StringName] = []
		for clip: StringName in clips:
			if clip in loops:
				looping.append(clip)
		return var_to_str([clips, looping, rates, glow.resource_path, max_error])


## A character's meshes merged (merge): one surface's arrays; each mesh's triangles in it (indices into them), whether
## it glows, its node, and its first vertex in the arrays.
class Merged:
	var arrays: Array
	var parts: Array[PackedInt32Array] = []
	var glowing: Array[bool] = []
	var meshes: Array[MeshInstance3D] = []
	var bases: PackedInt32Array = []

	## The mesh (its index in `meshes`) merged vertex `vertex` comes from.
	func mesh_of(vertex: int) -> int:
		var mesh: int = 0
		while mesh + 1 < bases.size() and bases[mesh + 1] <= vertex:
			mesh += 1
		return mesh


## A merged character lightened (lighten): the crowd surface's arrays, and for each of its vertices the merged vertex it
## is.
class Lightened:
	var arrays: Array = []
	var source: PackedInt32Array = []


## A character's bake: its mesh (one surface) and its clips.
class Baked:
	var mesh: ArrayMesh
	var clips: CrowdClips
