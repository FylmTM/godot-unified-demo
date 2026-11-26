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
## The most clips a crowd's shader takes (its uniform arrays' size).
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
## Per clip: whether it loops (Clips.LOOPING).
@export var loops: Array[bool] = []
## The skeleton's bones.
@export var bone_count: int = 0
## Every pose's bounds in the crowd's mesh space, for its MultiMesh's culling (a riser starts below the floor).
@export var bounds: AABB
## What the bake was made from: a hash of its inputs' bytes (CrowdBake.sources), so a check can tell it is stale.
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


## Bone `bone`'s skinning matrix in clip `clip_index` at `seconds` into it, blended between its two frames: what the
## shader computes, on the CPU (the art checks compare it with the character scene's pose).
func matrix(clip_index: int, seconds: float, bone: int) -> Transform3D:
	var frames: int = frame_counts[clip_index]
	var clip_length: float = length(clip_index)
	var held: float = fposmod(seconds, clip_length) if loops[clip_index] else clampf(seconds, 0.0, clip_length)
	var at: float = held * rates[clip_index]
	var frame: int = mini(floori(at), frames - 2)
	var blend: float = at - frame
	var row: int = first_rows[clip_index] + frame
	var rows: Array[Vector4] = []
	for texel: int in TEXELS_PER_BONE:
		var x: int = bone * TEXELS_PER_BONE + texel
		var a: Color = bones.get_pixel(x, row)
		var b: Color = bones.get_pixel(x, row + 1)
		rows.append(Vector4(a.r, a.g, a.b, a.a).lerp(Vector4(b.r, b.g, b.b, b.a), blend))
	return Transform3D(
		Basis(Vector3(rows[0].x, rows[1].x, rows[2].x), Vector3(rows[0].y, rows[1].y, rows[2].y),
			Vector3(rows[0].z, rows[1].z, rows[2].z)),
		Vector3(rows[0].w, rows[1].w, rows[2].w))
