class_name CharacterRig
extends Node3D
## A KayKit character as the game shows it: the model on the shared Rig_Medium skeleton, its weapons in its hands, and
## one AnimationPlayer (rig_animations.tscn) that plays every clip library.
##
## Nothing here advances on its own. The player is in manual mode, and pose() sets the whole pose from a clip and a time
## in it. A view computes that time from the simulation's state (what the character is doing, and since which tick), so
## after a rollback or a replay seek the character shows exactly the frame the state says, never a frame left over
## from a prediction that turned out wrong.

## The bones of KayKit's Rig_Medium, which every hero and skeleton shares: clips address them by name
## (`Rig_Medium/Skeleton3D:<bone>`), so one library animates every character. The art checks
## (game/tools/art_checks.gd) hold each character scene to this list.
const BONES: PackedStringArray = [
	"root", "hips", "spine", "chest", "head",
	"upperarm.l", "lowerarm.l", "wrist.l", "hand.l", "handslot.l",
	"upperarm.r", "lowerarm.r", "wrist.r", "hand.r", "handslot.r",
	"upperleg.l", "lowerleg.l", "foot.l", "toes.l",
	"upperleg.r", "lowerleg.r", "foot.r", "toes.r",
]

## The clip shown now (`Library/Clip`, one of Clips), empty before the first pose().
var clip: StringName = &""

@onready var _player: AnimationPlayer = $AnimationPlayer


## Shows `clip_name` (`Library/Clip`, one of Clips) at `seconds` into it. A looping clip (Clips.LOOPING) wraps, so
## `seconds` may be any time since it started; a one-shot clip holds its last frame past its end.
func pose(clip_name: StringName, seconds: float) -> void:
	if clip_name != clip:
		clip = clip_name
		_player.play(clip_name)
	var length: float = _player.current_animation_length
	_player.seek(fposmod(seconds, length) if clip_name in Clips.LOOPING else minf(seconds, length), true)
