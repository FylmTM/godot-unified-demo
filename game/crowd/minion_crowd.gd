class_name MinionCrowd
extends RefCounted
## The skeleton minions drawn as a crowd: the clips an instance names, where the bake is kept, and the material that
## draws it (material(): crowd_minion.gdshader, its look taken from where each part of it lives). What the bake makes
## of the minion is a tool's (game/tools/minion_bake.gd): a running game loads only what is here.
##
## An instance of the crowd is a minion: its transform the minion's feet and facing, its custom data the pose (a clip of
## CLIPS by index, and the seconds since it began) and the seconds since it was last struck (its flash), as the
## shader's header says.

## An instance's clip (INSTANCE_CUSTOM.x): CLIPS' order.
enum Clip { IDLE, WALK, ATTACK, RISE, DEATH }

## The clips a minion plays, in the order an instance names them (Clip).
const CLIPS: Array[StringName] = [
	Clips.SKELETON_IDLE,
	Clips.SKELETON_WALK,
	Clips.SKELETON_ATTACK,
	Clips.SKELETON_RISE,
	Clips.SKELETON_DEATH,
]
## The scene's material that glows: the eyes (the bake keeps them whole and marks them 1 in UV2, its only masked
## material; the crowd draws them with its colours).
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
## How long a hit's flash lasts, in ticks of shown game time.
const FLASH_TICKS: float = 8.0
## How long the dying take to sink out of sight, the end of their row's DEATH_S.
const SINK_S: float = 0.6
## How much deeper than its last pose's top a dead minion sinks: under the floor's relief.
const SINK_MARGIN: float = 0.05


## The crowd's material: the shader, its clip table and bone texture from the committed bake, and its look from where
## each part lives (the palette and roughness from the scene's skeleton material, the eyes from its glow, the flash
## from hit_flash.tres and FLASH_TICKS, the sink from DEATH_S and the death clip's last pose). Where in a clip an action
## starts (its clip_offset) is the view's (game/crowd/minion_crowd_view.gd).
static func material() -> ShaderMaterial:
	var crowd := ShaderMaterial.new()
	crowd.shader = load(SHADER)
	var clips: UnifiedCrowdClips = load(TABLE)
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
	crowd.set_shader_parameter("flash_s", FLASH_TICKS / Unified.tick_hz)
	var death_s: float = Unified.constants.minion_death
	crowd.set_shader_parameter("death_clip", Clip.DEATH)
	crowd.set_shader_parameter("sink_from", death_s - SINK_S)
	crowd.set_shader_parameter("sink_until", death_s)
	crowd.set_shader_parameter("sink_depth", clips.last_bounds[Clip.DEATH].end.y + SINK_MARGIN)
	return crowd
