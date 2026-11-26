class_name RagdollView
extends Node3D
## A downed hero's ragdoll (View_Ragdoll, simulation/extension/frame.odin): the host poses this root at the ragdoll's
## pelvis, turned as the pelvis is from its rest pose, and the script shows the hero's class's character
## (game/characters/heroes/) bone by bone on its Rig_Medium skeleton.
##
## The ragdoll's bones aren't the rig's: its rest pose stands with its arms down, the rig's is a T-pose, and the rig's
## legs are shorter (a KayKit hero's big head). So the torso's bones (hips, spine, chest, head) take the ragdoll's
## bones' turns from their rest pose as they are (both stand upright, facing +Z), and each limb bone is swung, the least
## turn from where its parent's turn carries its rest direction, to point along its ragdoll bone (the data's
## `reaches`): its twist is its parent's. The rig rides the root with its hip joints on the pelvis. The pose is a function of the data
## alone, set when the data changes, so a rollback or a replay seek shows what the state says; the host interpolates
## the root between ticks. It lingers not at all (its marker's linger_s): a revived hero's own view stands up where the
## body lay that very tick, and two bodies would show.

## The rig's bone each ragdoll bone poses, in physics.Ragdoll_Bone's order (unified's ragdoll.odin): the torso's four
## first, turned whole, then the limbs.
const BONES: Array[StringName] = [
	&"hips", &"spine", &"chest", &"head",
	&"upperleg.l", &"lowerleg.l", &"upperleg.r", &"lowerleg.r",
	&"upperarm.l", &"lowerarm.l", &"upperarm.r", &"lowerarm.r",
]
## How many of BONES are the torso's (turned whole); the rest are limbs (swung along their reach).
const TORSO: int = 4
## The rig's bone each limb of BONES points at (its rest direction runs from the limb's bone to this one), by BONES'
## index.
const LIMB_ENDS: Dictionary[int, StringName] = {
	4: &"lowerleg.l", 5: &"foot.l", 6: &"lowerleg.r", 7: &"foot.r",
	8: &"lowerarm.l", 9: &"wrist.l", 10: &"lowerarm.r", 11: &"wrist.r",
}

## Each class's character.
@export var knight: PackedScene
@export var barbarian: PackedScene
@export var mage: PackedScene
@export var rogue: PackedScene

## Set by the host before _ready, and anew each time the ragdoll's view data changes.
var data: ViewRagdoll:
	set(value):
		var class_changed: bool = data == null or data.class != value.class
		data = value
		if not is_node_ready():
			return
		if class_changed:
			_show_class()
		_pose()

var _rig: CharacterRig
var _skeleton: Skeleton3D
## By BONES' index: the rig bone's index, its parent's index in BONES (-1: the hips, whose parent is the rig's root
## bone, left at rest), its global rest transform, and (a limb's) its rest direction.
var _bones: PackedInt32Array
var _parents: PackedInt32Array
var _rests: Array[Transform3D] = []
var _directions: PackedVector3Array


func _ready() -> void:
	_show_class()
	_pose()


## Poses the rig from the data: each of BONES in order (a parent before its children) turned from its rest, the
## torso's by its ragdoll bone's turn, a limb's by the least swing from where its parent's turn carries its rest
## direction onto its reach, then its parent's turn; its local pose rotation is what that leaves of its parent's.
func _pose() -> void:
	var turns: Array = data.turns
	var reaches: Array = data.reaches
	var turned: Array[Quaternion] = []
	var globals: Array[Basis] = []
	for i: int in BONES.size():
		var parent: int = _parents[i]
		var parent_turn: Quaternion = Quaternion.IDENTITY if parent < 0 else turned[parent]
		var turn: Quaternion = turns[i]
		if i >= TORSO:
			var reach: Vector3 = reaches[i]
			turn = Quaternion(parent_turn * _directions[i], reach) * parent_turn
		turned.append(turn)
		globals.append(Basis(turn) * _rests[i].basis)
		var parent_global: Basis = (_skeleton.get_bone_global_rest(_skeleton.get_bone_parent(_bones[i])).basis
			if parent < 0 else globals[parent])
		_skeleton.set_bone_pose_rotation(_bones[i], (parent_global.inverse() * globals[i]).get_rotation_quaternion())


## Replaces the character with the class's, in its rest pose, its hip joints on the root.
func _show_class() -> void:
	if _rig != null:
		_rig.free()
	_rig = _class_scene().instantiate() as CharacterRig
	add_child(_rig)
	_skeleton = _rig.get_node(^"Model/Rig_Medium/Skeleton3D") as Skeleton3D
	_skeleton.reset_bone_poses()
	_bones.clear()
	_parents.clear()
	_rests.clear()
	_directions.clear()
	for i: int in BONES.size():
		var bone: int = _skeleton.find_bone(BONES[i])
		_bones.append(bone)
		_parents.append(BONES.find(_skeleton.get_bone_name(_skeleton.get_bone_parent(bone))))
		_rests.append(_skeleton.get_bone_global_rest(bone))
		var direction := Vector3.ZERO
		if LIMB_ENDS.has(i):
			var end: Vector3 = _skeleton.get_bone_global_rest(_skeleton.find_bone(LIMB_ENDS[i])).origin
			direction = (end - _rests[i].origin).normalized()
		_directions.append(direction)
	_rig.position = -(_rests[BONES.find(&"upperleg.l")].origin + _rests[BONES.find(&"upperleg.r")].origin) / 2.0


## The class's character scene (the Knight's for a class no hero plays: `Any`).
func _class_scene() -> PackedScene:
	match data.class:
		EnumClass.BARBARIAN:
			return barbarian
		EnumClass.MAGE:
			return mage
		EnumClass.ROGUE:
			return rogue
	return knight
