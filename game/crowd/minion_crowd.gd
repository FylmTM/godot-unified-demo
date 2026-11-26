class_name MinionCrowd
extends RefCounted
## The skeleton minions drawn as a crowd: what CrowdBake bakes for them (`./uni tool bake_crowd`), where the bake is
## kept, and the material that draws it (material(): crowd_minion.gdshader, its look taken from where each part of it
## lives).
##
## An instance of the crowd is a minion: its transform the minion's feet and facing, its custom data the pose (a clip of
## CLIPS by index, and the seconds since it began) and the seconds since it was last struck (its flash), as the
## shader's header says.

## An instance's clip (INSTANCE_CUSTOM.x): CLIPS' order.
enum Clip { IDLE, WALK, ATTACK, RISE, DEATH }

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
## their shape); within it the scene's 5,745 triangles become 2,425, the head, jaw and eyes whole.
const LOD_ERROR: float = 0.11
## The most triangles the crowd minion may have (the art checks): 500 of them a pass.
const TRIANGLES: int = 2450
## The scene's material that glows: the eyes (the crowd marks them in UV2, and draws them with its colours).
const GLOW: String = "res://game/materials/skeleton_glow.tres"
## The scene's material for the rest: the palette atlas and its roughness.
const SKIN: String = "res://game/materials/skeleton.tres"
## A hit's flash: its colour.
const FLASH: String = "res://game/fx/hit_flash.tres"
## The bake: the merged mesh, the clips' bone matrices (an Image), and the clip table that names them.
const MESH: String = "res://game/crowd/minion_mesh.res"
const BONES: String = "res://game/crowd/minion_bones.res"
const TABLE: String = "res://game/crowd/minion_clips.tres"
## The crowd's shader.
const SHADER: String = "res://game/crowd/crowd_minion.gdshader"
## How long the dying take to sink out of sight, the end of their row's DEATH_S.
const SINK_S: float = 0.6
## How much deeper than its last pose's top a dead minion sinks: under the floor's relief.
const SINK_MARGIN: float = 0.05


## What the bake makes of the minion.
static func recipe() -> CrowdBake.Recipe:
	var out := CrowdBake.Recipe.new()
	out.clips = CLIPS
	out.loops = Clips.LOOPING
	out.rates = RATES
	out.glow = load(GLOW)
	out.max_error = LOD_ERROR
	return out


## Bakes the minion: `rig` is a SCENE instance in the tree. The result's clips carry the hash of the bake's inputs.
static func bake(rig: CharacterRig) -> CrowdBake.Baked:
	var baked: CrowdBake.Baked = CrowdBake.bake(rig, rig.pose, recipe())
	baked.clips.sources = inputs_hash()
	return baked


## The hash of what the bake is made from now: the recipe, the scene and everything it loads, and the bake's code.
static func inputs_hash() -> String:
	return CrowdBake.inputs_hash(recipe(), CrowdBake.input_files(SCENE))


## The crowd's material: the shader, its clip table and bone texture from the committed bake, and its look from where
## each part lives (the palette and roughness from the scene's skeleton material, the eyes from its glow, the flash
## from hit_flash.tres and MinionView's FLASH_TICKS, the sink from DEATH_S and the death clip's last pose).
static func material() -> ShaderMaterial:
	var crowd := ShaderMaterial.new()
	crowd.shader = load(SHADER)
	var clips: CrowdClips = load(TABLE)
	clips.apply(crowd)
	var skin: StandardMaterial3D = load(SKIN)
	var glow: StandardMaterial3D = load(GLOW)
	var flash: StandardMaterial3D = load(FLASH)
	crowd.set_shader_parameter("palette", skin.albedo_texture)
	crowd.set_shader_parameter("roughness", skin.roughness)
	crowd.set_shader_parameter("eye_color", glow.albedo_color)
	crowd.set_shader_parameter("eye_emission", glow.emission)
	crowd.set_shader_parameter("eye_energy", glow.emission_energy_multiplier)
	crowd.set_shader_parameter("flash_color", flash.albedo_color)
	crowd.set_shader_parameter("flash_s", MinionView.FLASH_TICKS / Unified.tick_hz)
	var death_s: float = Unified.constants.minion_death
	crowd.set_shader_parameter("death_clip", Clip.DEATH)
	crowd.set_shader_parameter("sink_from", death_s - SINK_S)
	crowd.set_shader_parameter("sink_until", death_s)
	crowd.set_shader_parameter("sink_depth", clips.tops[Clip.DEATH] + SINK_MARGIN)
	return crowd
