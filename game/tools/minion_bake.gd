class_name MinionBake
extends RefCounted
## What unified's crowd bake makes of the skeleton minion (recipe()): the minion scene, MinionCrowd's clips at their
## rates, the eyes kept whole and marked, how far the rest is lightened, and where the bake goes (MinionCrowd's
## paths). Bake-time only: `./uni tool bake_crowd` bakes it, the art checks run UnifiedCrowdCheck on it, and nothing a
## running game loads names it.

## The character the crowd is baked from: the minion scene the game showed each minion as, weapon and all.
const SCENE: String = "res://game/characters/skeletons/minion.tscn"
## The frames a second each of MinionCrowd.CLIPS is baked at: its keys' rate (KayKit's 30) for the stance and the
## gait, four times it for the swing, the rise and the fall, whose bones turn up to 70 and 130 degrees between keys: at
## 30 a blend of two frames' matrices cuts such a turn's arc by up to 15 cm, at 120 by about 1 (the art checks hold it
## within CROWD_PARITY). Whether a clip loops is its import's (Clips.LOOPING, held equal by the art checks).
const RATES: PackedFloat32Array = [30.0, 30.0, 120.0, 120.0, 120.0]
## How far the bake lightens each of the minion's meshes: Godot's LOD error, relative to the mesh's size. Past it the
## minion's LOD chains jump (an arm or a leg to 0.15 and on, the body, head, cloak and blade to about 0.4: they lose
## their shape); within it the scene's 5,745 triangles become 2,425, the head, jaw and eyes whole.
const LOD_ERROR: float = 0.11
## The most triangles the crowd minion may have (the crowd check): 500 of them a pass.
const TRIANGLES: int = 2450


## What the bake makes of the minion, and where it is kept.
static func recipe() -> UnifiedCrowdRecipe:
	var out := UnifiedCrowdRecipe.new()
	out.scene = SCENE
	for index: int in MinionCrowd.CLIPS.size():
		out.clips.append(UnifiedCrowdClip.new(MinionCrowd.CLIPS[index], RATES[index]))
	out.masked = [load(MinionCrowd.GLOW) as Material]
	out.max_error = LOD_ERROR
	out.max_triangles = TRIANGLES
	out.pose = func(rig: Node3D, clip: StringName, seconds: float) -> void: (rig as CharacterRig).pose(clip, seconds)
	out.mesh_path = MinionCrowd.MESH
	out.bones_path = MinionCrowd.BONES
	out.clips_path = MinionCrowd.TABLE
	return out
