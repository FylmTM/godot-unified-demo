class_name MinionCrowd
extends RefCounted
## The skeleton minions drawn as a crowd: what CrowdBake bakes for them (`./uni tool bake_crowd`), where the bake is
## kept, and the material that draws it (crowd_minion.tres, its shader crowd_minion.gdshader).
##
## An instance of the crowd is a minion: its transform the minion's feet and facing, its custom data the pose (a clip of
## CLIPS by index, and the seconds since it began) and the seconds since it was last struck (its flash), as the
## shader reads them.

## The character the crowd is baked from: the minion scene the game showed each minion as, weapon and all.
const SCENE: String = "res://game/characters/skeletons/minion.tscn"
## The clips a minion plays, in the order an instance names them (Clip).
const CLIPS: Array[StringName] = [
	Clips.SKELETON_IDLE,
	Clips.SKELETON_WALK,
	Clips.SKELETON_ATTACK,
	Clips.SKELETON_RISE,
	Clips.SKELETON_DEATH,
]
## The frames a second each clip is baked at: its keys' rate (KayKit's 30) for the stance and the gait, four times it
## for the swing, the rise and the fall, whose bones turn up to 70 and 130 degrees between keys: at 30 a blend of two
## frames' matrices cuts such a turn's arc by up to 15 cm, at 120 by about 1 (the art checks hold it within
## CROWD_PARITY).
const RATES: PackedFloat32Array = [30.0, 30.0, 120.0, 120.0, 120.0]
## How far the bake lightens each of the minion's meshes: Godot's LOD error, relative to the mesh's size. Past it the
## minion's LOD chains jump (an arm or a leg to 0.15 and on, the body, head, cloak and blade to about 0.4: they lose
## their shape); within it the scene's 5,745 triangles become about 2,300, the head and jaw whole.
const LOD_ERROR: float = 0.11
## The most triangles the crowd minion may have (the art checks): 500 of them a pass.
const TRIANGLES: int = 2400
## The scene's material that glows: the eyes (the crowd marks them in the vertex colour).
const GLOW: String = "res://game/materials/skeleton_glow.tres"
## The bake: the merged mesh, the clips' bone matrices (an Image), and the clip table that names them.
const MESH: String = "res://game/crowd/minion_mesh.res"
const BONES: String = "res://game/crowd/minion_bones.res"
const TABLE: String = "res://game/crowd/minion_clips.tres"
## The crowd's material: its look (the palette, the eyes, the flash, the sink); the clip table is set on it at load.
const MATERIAL: String = "res://game/crowd/crowd_minion.tres"
## The bake's own code: a change to it is a change to the bake (the art checks' freshness hash covers it).
const SCRIPTS: PackedStringArray = [
	"res://game/crowd/crowd_bake.gd", "res://game/crowd/crowd_clips.gd", "res://game/crowd/minion_crowd.gd",
]

## An instance's clip (INSTANCE_CUSTOM.x): CLIPS' order.
enum Clip { IDLE, WALK, ATTACK, RISE, DEATH }


## Bakes the minion: `rig` is a SCENE instance in the tree. The result's clips carry the hash of the bake's inputs.
static func bake(rig: CharacterRig) -> CrowdBake.Baked:
	var baked: CrowdBake.Baked = CrowdBake.bake(rig, load(GLOW) as Material, LOD_ERROR, CLIPS, RATES)
	baked.clips.sources = sources()
	return baked


## The hash of what the bake is made from now: the scene and everything it loads, and the bake's code.
static func sources() -> String:
	return CrowdBake.sources(CrowdBake.inputs(SCENE, SCRIPTS))


## The crowd's material, its clip table and bone texture set from the committed bake.
static func material() -> ShaderMaterial:
	var crowd: ShaderMaterial = load(MATERIAL)
	(load(TABLE) as CrowdClips).apply(crowd)
	return crowd
