extends MultiMeshInstance3D
## The minions in play: one MultiMesh of the baked minion (MinionCrowd), filled by its UnifiedMultiView from the
## extension's minion_instance (simulation/extension/frame.odin), each instance posed by crowd_minion.gdshader from its
## custom data: its clip, its clip's age and its last hit's age, which the host writes at the shown time.
##
## The shader draws all a minion does: the rise, the walk and the stance, the swing, the fall and the sink, the eyes, a
## hit's flash (as bright as Settings.flashes says: Flashes). What is set here is the art's timing: where in a clip an action starts, so that the sim's moments land
## on the clip's (the swing's blow on the windup's end; the art checks hold both offsets to the sim's numbers).

## Where in the rise clip a minion starts: its last RISE_S (1.5 s) of 2.3, from the hand breaking the floor.
const RISE_FROM: float = 0.8
## When the attack clip's blow lands (seconds in: where the hand moves fastest); the clip is offset so it lands at the
## sim's swing (Unified.constants.minion_windup).
const BLOW_AT: float = 0.6


func _ready() -> void:
	var crowd: ShaderMaterial = MinionCrowd.material()
	var offsets: PackedFloat32Array = []
	offsets.resize(MinionCrowd.Clip.size())
	offsets[MinionCrowd.Clip.RISE] = RISE_FROM
	offsets[MinionCrowd.Clip.ATTACK] = BLOW_AT - Unified.constants.minion_windup
	crowd.set_shader_parameter("clip_offset", offsets)
	crowd.set_shader_parameter("flash_strength", Flashes.strength(Settings.flashes))
	material_override = crowd
	Settings.changed.connect(func(setting: StringName) -> void:
		if setting == &"flashes":
			crowd.set_shader_parameter("flash_strength", Flashes.strength(Settings.flashes)))
