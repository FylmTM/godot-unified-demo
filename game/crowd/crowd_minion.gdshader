// The skeleton minions' crowd (MinionCrowd): one MultiMesh of the baked minion, each instance posed by its custom
// data and skinned by unified's crowd skinning from the baked bone matrices (UnifiedCrowdClips), so the whole crowd is
// one draw call a pass and its animation costs no node. Matte on the skeletons' palette atlas, as
// game/materials/skeleton.tres draws the scene minion; the eyes (the bake's mask, UV2's x: 1, the eyes' material the only one masked) glow as skeleton_glow.tres
// does. MinionCrowd.material() sets every uniform from where it lives.
//
// INSTANCE_CUSTOM, the contract a crowd's view keeps (simulation/extension/frame.odin's minion_instance writes game-time
// stamps, which the minion kind's policy, MULTI_POLICY's ages, turns into seconds since them at the shown time):
// - x: the clip, MinionCrowd.Clip (clamped to CLIPS).
// - y: the seconds into the clip. A one-shot's stamp is the tick its action began. A loop's is minus the minion's phase
//   (a far-past, per-minion stamp), so the crowd's gaits don't walk in lockstep and a walk doesn't restart when a
//   minion stops and starts again.
// - z: the seconds since the minion was last struck (its flash). A minion never struck carries a far-past stamp: a 0
//   stamp would age as the shown time itself and flash every minion in a session's first ticks.
// - w: spare, 0.
// The ages are seconds at the shown time, so a pause holds a pose and a replay seek shows the pose the state says.
shader_type spatial;

// The skinning: the bake's bone texture (its clip table in its header row), set by UnifiedCrowdClips.apply.
#include "res://unified/godot_runtime/crowd_skin.gdshaderinc"

// The clips an instance names (MinionCrowd.Clip, held equal by the art checks).
const int CLIPS = 5;

// Per clip, seconds added to its age: where in the clip an action starts (the art's timing, as the view sets it).
uniform float clip_offset[CLIPS];

uniform sampler2D palette : source_color, filter_linear;
uniform float roughness = 0.7;
// The eyes: skeleton_glow.tres's albedo, its emission and its emission's energy (above the glow threshold: they bloom).
uniform vec3 eye_color : source_color = vec3(1.0, 1.0, 0.19);
uniform vec3 eye_emission : source_color = vec3(1.0, 1.0, 0.19);
uniform float eye_energy = 4.0;
// A hit's flash: hit_flash.tres's colour, added for flash_s after the blow (MinionCrowd.FLASH_TICKS).
uniform vec3 flash_color : source_color = vec3(0.9, 0.75, 0.55);
uniform float flash_s = 0.125;
// How bright the flash is: 1, or a half with Settings.flashes off (MinionCrowd).
uniform float flash_strength = 1.0;
// The dying sink into the floor over their last moments, out of sight before their row is freed: the death clip, from
// and until when (seconds into it), and how deep (deeper than its last pose's top).
uniform int death_clip = 4;
uniform float sink_from = 1.4;
uniform float sink_until = 2.0;
uniform float sink_depth = 1.0;

varying float flash;

void vertex() {
	int clip = clamp(int(INSTANCE_CUSTOM.x + 0.5), 0, CLIPS - 1);
	float age = INSTANCE_CUSTOM.y + clip_offset[clip];
	mat4 skin = unified_crowd_skinning(clip, age, CUSTOM0, CUSTOM1);
	VERTEX = (skin * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(mat3(skin) * NORMAL);
	if (clip == death_clip) {
		VERTEX.y -= sink_depth * clamp((age - sink_from) / (sink_until - sink_from), 0.0, 1.0);
	}
	flash = INSTANCE_CUSTOM.z < flash_s ? 1.0 : 0.0;
}

void fragment() {
	float eye = UV2.x;
	ALBEDO = mix(texture(palette, UV).rgb, eye_color, eye);
	ROUGHNESS = roughness;
	EMISSION = eye_emission * eye_energy * eye + flash_color * flash * flash_strength;
}
