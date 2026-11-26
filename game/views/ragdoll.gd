class_name RagdollView
extends Node3D
## A downed hero's ragdoll (View_Ragdoll, simulation/extension/frame.odin): the host poses this root at the ragdoll's
## pelvis, turned as the pelvis is from its rest pose, and the script shows the hero's class's character
## (game/characters/heroes/) bone by bone on its Rig_Medium skeleton.
##
## The ragdoll's bones aren't the rig's: its rest pose stands with its arms down, the rig's is a T-pose, and the rig's
## legs are shorter (a KayKit hero's big head). Each rig bone takes its ragdoll bone's turn from its rest pose (the
## data's `turns`); a limb's first the turn that takes the rig's rest direction onto the ragdoll bone's rest direction
## (its reach turned back by its turn: the same whatever the pose), so an arm hanging at rest hangs, and a knee or an
## elbow bends in its own plane. The rig rides the root with its hip joints on the pelvis. The pose is a function of the
## data and the shown time alone: each bone's turn eases from what is shown when new data comes to the data's, by the
## shown time reaching the data's tick (`time`), as the host moves the root between ticks, so a tumble doesn't step at
## the tick rate, and a rollback or a replay seek lands on what the state says. It lingers not at all (its marker's
## linger_s): a revived hero's own view stands up where the body lay that very tick, and two bodies would show.

## The rig's bone each ragdoll bone poses, in physics.Ragdoll_Bone's order (unified's ragdoll.odin): the torso's four
## first, then the limbs.
const BONES: Array[StringName] = [
	&"hips", &"spine", &"chest", &"head",
	&"upperleg.l", &"lowerleg.l", &"upperleg.r", &"lowerleg.r",
	&"upperarm.l", &"lowerarm.l", &"upperarm.r", &"lowerarm.r",
]
## How many of BONES are the torso's (their rest directions match the rig's: upright).
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
		_aim()

var _rig: CharacterRig
var _skeleton: Skeleton3D
## By BONES' index: the rig bone's index, its parent's index in BONES (-1: the hips, whose parent is the rig's root
## bone, left at rest), its global rest transform, and (a limb's) its rest direction.
var _bones: PackedInt32Array
var _parents: PackedInt32Array
var _rests: Array[Transform3D] = []
var _directions: PackedVector3Array
## By BONES' index: each bone's turn as shown when the data last came, and the data's; the shown time then, and the
## data's tick.
var _from: Array[Quaternion] = []
var _to: Array[Quaternion] = []
var _from_time: float = 0.0
var _to_time: float = 0.0
## How far from _from to _to the bones were last posed (0 to 1).
var _weight: float = 0.0


func _ready() -> void:
	_show_class()
	_aim()


func _process(_delta: float) -> void:
	var now: float = Unified.session.shown_time
	var weight: float = 1.0 if _to_time <= _from_time else clampf((now - _from_time) / (_to_time - _from_time), 0.0, 1.0)
	_pose(weight)


## New data: each bone eases from where it is shown now to the data's turn (_turn), by the shown time reaching its tick.
func _aim() -> void:
	var shown: Array[Quaternion] = []
	if _to.size() == BONES.size():
		for i: int in BONES.size():
			shown.append(_shown(i))
	_from_time = Unified.session.shown_time
	_to_time = float(data.time)
	_to.clear()
	for i: int in BONES.size():
		_to.append(_turn(i))
	_from = shown if not shown.is_empty() else _to.duplicate()
	_pose(0.0)


## The turn of bone `i` of BONES from its rest pose, in the root's frame, as the data has it: its ragdoll bone's turn,
## a limb's after the turn from the rig's rest direction onto the ragdoll bone's (its reach turned back by its turn).
func _turn(i: int) -> Quaternion:
	var turn: Quaternion = data.turns[i]
	if i < TORSO:
		return turn
	var reach: Vector3 = data.reaches[i]
	return turn * Quaternion(_directions[i], turn.inverse() * reach)


## Bone `i`'s turn as shown now: as far from its old turn to the data's as _process last posed it.
func _shown(i: int) -> Quaternion:
	return _from[i].slerp(_to[i], _weight)


## Poses the rig `weight` of the way from the turns shown when the data came to the data's: each of BONES in order (a
## parent before its children), its global rest turned, its local pose rotation what that leaves of its parent's.
func _pose(weight: float) -> void:
	_weight = weight
	var globals: Array[Basis] = []
	for i: int in BONES.size():
		globals.append(Basis(_shown(i)) * _rests[i].basis)
		var parent: int = _parents[i]
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
