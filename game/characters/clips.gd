class_name Clips
extends RefCounted
## The animation clips the game plays, named for what they show, each as `Library/Clip` in rig_animations.tscn's
## libraries (KayKit's Rig_Medium clip files, in assets/kaykit/animations/).
##
## This is the one list of clips the game depends on, and the one place that says which loop: a view names a clip
## through these constants, never by its KayKit name, and CharacterRig.pose() wraps the looping ones itself (the
## imported clips keep KayKit's own, unlooped settings). The art checks (game/tools/art_checks.gd) prove every constant
## here names a clip that exists and moves only Rig_Medium bones.

# Every character.
const IDLE: StringName = &"General/Idle_A"
const IDLE_ALT: StringName = &"General/Idle_B"
const WALK: StringName = &"MovementBasic/Walking_A"
const RUN: StringName = &"MovementBasic/Running_A"
const WALK_BACKWARDS: StringName = &"MovementAdvanced/Walking_Backwards"
const STRAFE_LEFT: StringName = &"MovementAdvanced/Running_Strafe_Left"
const STRAFE_RIGHT: StringName = &"MovementAdvanced/Running_Strafe_Right"
const HIT: StringName = &"General/Hit_A"
const HIT_ALT: StringName = &"General/Hit_B"
const DEATH: StringName = &"General/Death_A"
const INTERACT: StringName = &"General/Interact"
const PICK_UP: StringName = &"General/PickUp"
const THROW: StringName = &"General/Throw"

# Heroes, by class.
const DODGE_FORWARD: StringName = &"MovementAdvanced/Dodge_Forward"
const KNIGHT_SLASH: StringName = &"CombatMelee/Melee_1H_Attack_Slice_Horizontal"
const KNIGHT_CHOP: StringName = &"CombatMelee/Melee_1H_Attack_Chop"
const KNIGHT_BLOCK: StringName = &"CombatMelee/Melee_Blocking"
const BARBARIAN_IDLE: StringName = &"CombatMelee/Melee_2H_Idle"
const BARBARIAN_CLEAVE: StringName = &"CombatMelee/Melee_2H_Attack_Slice"
const BARBARIAN_SPIN: StringName = &"CombatMelee/Melee_2H_Attack_Spin"
const MAGE_BOLT: StringName = &"CombatRanged/Ranged_Magic_Shoot"
const MAGE_CAST: StringName = &"CombatRanged/Ranged_Magic_Spellcasting"
const ROGUE_AIM: StringName = &"CombatRanged/Ranged_2H_Aiming"
const ROGUE_SHOOT: StringName = &"CombatRanged/Ranged_2H_Shoot"
const ROGUE_RUN: StringName = &"MovementAdvanced/Running_HoldingRifle"

# Skeletons.
const SKELETON_IDLE: StringName = &"Special/Skeletons_Idle"
const SKELETON_WALK: StringName = &"Special/Skeletons_Walking"
const SKELETON_RISE: StringName = &"Special/Skeletons_Awaken_Floor"
const SKELETON_DEATH: StringName = &"Special/Skeletons_Death"
const SKELETON_TAUNT: StringName = &"Special/Skeletons_Taunt"
const SKELETON_ATTACK: StringName = &"CombatMelee/Melee_1H_Attack_Chop"

## The clips that loop: a stance or a gait, shown for as long as it lasts, each ending in the pose it starts with (the
## checks prove it). Every other clip is a one-shot: the Rogue's aim raises the crossbow and holds it raised.
const LOOPING: Array[StringName] = [
	IDLE, IDLE_ALT, WALK, RUN, WALK_BACKWARDS, STRAFE_LEFT, STRAFE_RIGHT, KNIGHT_BLOCK, BARBARIAN_IDLE, MAGE_CAST,
	ROGUE_RUN, SKELETON_IDLE, SKELETON_WALK,
]
