class_name CrowdClips
extends Resource
## A crowd's baked clips (CrowdBake): every frame of each clip as the bones' skinning matrices, a row of `bones` per
## frame and TEXELS_PER_BONE texels per bone (the three rows of its 3x4 matrix, RGBA float), and the table a crowd's
## shader finds a clip's frames by (game/crowd/crowd_minion.gdshader). A pose is a clip and a time in it, as
## CharacterRig.pose() takes: a looping clip wraps, a one-shot holds its first frame before its start and its last past
## its end; between two frames the matrices blend.
##
## A clip's frames are 0 to its length at its rate, both ends included: a looping clip's last frame is its first pose
## again (the art checks prove the loops seamless), so a blend never wraps. A blend of two frames' matrices is linear,
## where the scene turns each bone along an arc: a clip whose bones turn fast between keys is baked at a multiple of
## its keys' rate, so the blend stays near the arc.

## The texels a bone takes in a row.
const TEXELS_PER_BONE: int = 3
## The most clips a crowd's shader takes: its uniform arrays' size (the shader's own MAX_CLIPS, which the art checks
## hold equal).
const MAX_CLIPS: int = 8

## The matrices: (bone_count * TEXELS_PER_BONE) by the frames of every clip, RGBA float.
@export var bones: Image
## The clips, as CharacterRig names them (`Library/Clip`), in the order an instance names them by index.
@export var clips: Array[StringName] = []
## Per clip: its first row in `bones`.
@export var first_rows: PackedInt32Array = []
## Per clip: its frames (its length times its rate, plus one).
@export var frame_counts: PackedInt32Array = []
## Per clip: the frames a second it is baked at.
@export var rates: PackedFloat32Array = []
## Per clip: whether it loops.
@export var loops: Array[bool] = []
## Per clip: the height of its last pose's highest point (how deep a sink must go to hide the end of a one-shot).
@export var tops: PackedFloat32Array = []
## The skeleton's bones.
@export var bone_count: int = 0
## Every pose's bounds in the crowd's mesh space, for its MultiMesh's culling (a riser starts below the floor).
@export var bounds: AABB
## What the bake was made from (CrowdBake.inputs_hash), so a check can tell it is stale.
@export var sources: String = ""


## The index of `clip` (an instance's clip channel), or -1.
func index(clip: StringName) -> int:
	return clips.find(clip)


## A clip's length in seconds, as baked.
func length(clip_index: int) -> float:
	return float(frame_counts[clip_index] - 1) / rates[clip_index]


## The texture the shader reads `bones` from.
func texture() -> ImageTexture:
	return ImageTexture.create_from_image(bones)


## Sets a crowd material's clip table and bone texture: what its shader needs to pose an instance.
func apply(material: ShaderMaterial) -> void:
	assert(clips.size() <= MAX_CLIPS, "%d clips: the shader takes %d" % [clips.size(), MAX_CLIPS])
	var first: PackedInt32Array = []
	var frames: PackedInt32Array = []
	var looping: PackedInt32Array = []
	var fps: PackedFloat32Array = []
	first.resize(MAX_CLIPS)
	frames.resize(MAX_CLIPS)
	looping.resize(MAX_CLIPS)
	fps.resize(MAX_CLIPS)
	for clip: int in clips.size():
		first[clip] = first_rows[clip]
		frames[clip] = frame_counts[clip]
		looping[clip] = int(loops[clip])
		fps[clip] = rates[clip]
	material.set_shader_parameter("bones", texture())
	material.set_shader_parameter("clip_first", first)
	material.set_shader_parameter("clip_frames", frames)
	material.set_shader_parameter("clip_loops", looping)
	material.set_shader_parameter("clip_fps", fps)


## Every bone's skinning matrix in clip `clip_index` at `seconds` into it, blended between its two frames: what the
## shader computes, on the CPU (the art checks compare it with the character scene's pose).
func matrices(clip_index: int, seconds: float) -> Array[Transform3D]:
	var frames: int = frame_counts[clip_index]
	var clip_length: float = length(clip_index)
	var held: float = fposmod(seconds, clip_length) if loops[clip_index] else clampf(seconds, 0.0, clip_length)
	var at: float = held * rates[clip_index]
	var frame: int = mini(floori(at), frames - 2)
	var blend: float = at - frame
	var row: int = first_rows[clip_index] + frame
	var out: Array[Transform3D] = []
	for bone: int in bone_count:
		out.append(_blend(frame_matrix(row, bone), frame_matrix(row + 1, bone), blend))
	return out


## Bone `bone`'s matrix in row `row` of `bones`, as baked.
func frame_matrix(row: int, bone: int) -> Transform3D:
	var x: int = bone * TEXELS_PER_BONE
	var r0: Color = bones.get_pixel(x, row)
	var r1: Color = bones.get_pixel(x + 1, row)
	var r2: Color = bones.get_pixel(x + 2, row)
	return Transform3D(Basis(Vector3(r0.r, r1.r, r2.r), Vector3(r0.g, r1.g, r2.g), Vector3(r0.b, r1.b, r2.b)),
		Vector3(r0.a, r1.a, r2.a))


## Two matrices blended entry by entry, as the shader blends two frames (not along an arc).
func _blend(a: Transform3D, b: Transform3D, weight: float) -> Transform3D:
	return Transform3D(
		Basis(a.basis.x.lerp(b.basis.x, weight), a.basis.y.lerp(b.basis.y, weight), a.basis.z.lerp(b.basis.z, weight)),
		a.origin.lerp(b.origin, weight))
