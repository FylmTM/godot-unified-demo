// The skeleton minions' crowd (MinionCrowd): one MultiMesh of the baked minion, each instance posed by its custom
// data and skinned here from the baked bone matrices (CrowdClips), so the whole crowd is one draw call a pass and its
// animation costs no node. Matte on the skeletons' palette atlas, as game/materials/skeleton.tres draws the scene
// minion; the eyes glow as skeleton_glow.tres does (the bake marks them in the vertex colour's red).
//
// INSTANCE_CUSTOM: x the clip (CrowdClips' index), y the seconds since it began, z the seconds since the minion was
// last struck (its hit flash), w spare. The ages are seconds at the shown time (the host's View_Policy.ages writes
// them so from game-time stamps), so a pause holds a pose and a replay seek shows the pose the state says.
shader_type spatial;

// The clips' bone matrices, three texels a bone (the rows of its 3x4 matrix), a row a frame (CrowdClips.apply).
uniform sampler2D bones : filter_nearest, repeat_disable;
// Per clip: its first row, its frames, whether it loops, its frames a second (CrowdClips.apply).
uniform int clip_first[8];
uniform int clip_frames[8];
uniform int clip_loops[8];
uniform float clip_fps[8];
// Per clip, seconds added to its age: where in the clip an action starts (the art's timing, as the view sets it).
uniform float clip_offset[8];

uniform sampler2D palette : source_color, filter_nearest;
uniform float roughness = 0.7;
// The eyes: skeleton_glow.tres's colour and energy (above the glow threshold: they bloom).
uniform vec3 eye_color : source_color = vec3(1.0, 1.0, 0.19);
uniform float eye_energy = 4.0;
// A hit's flash: game/fx/hit_flash.tres's colour, added for flash_s after the blow (the scene minion's 8 ticks).
uniform vec3 flash_color : source_color = vec3(0.9, 0.75, 0.55);
uniform float flash_s = 0.125;
// The dying sink into the floor over their last moments, so their row's freeing never pops: the death clip's index,
// from and until when (seconds into it), and how deep.
uniform int death_clip = 4;
uniform float sink_from = 1.4;
uniform float sink_until = 2.0;
uniform float sink_depth = 0.5;

varying float flash;

// Adds `weight` of `bone`'s matrix, blended between rows `row` and `row + 1` by `blend`, to the sum's three rows.
void add_bone(int bone, float weight, int row, float blend, inout vec4 r0, inout vec4 r1, inout vec4 r2) {
	int x = bone * 3;
	r0 += weight * mix(texelFetch(bones, ivec2(x, row), 0), texelFetch(bones, ivec2(x, row + 1), 0), blend);
	r1 += weight * mix(texelFetch(bones, ivec2(x + 1, row), 0), texelFetch(bones, ivec2(x + 1, row + 1), 0), blend);
	r2 += weight * mix(texelFetch(bones, ivec2(x + 2, row), 0), texelFetch(bones, ivec2(x + 2, row + 1), 0), blend);
}

void vertex() {
	int clip = int(INSTANCE_CUSTOM.x + 0.5);
	float age = INSTANCE_CUSTOM.y + clip_offset[clip];
	int frames = clip_frames[clip];
	float fps = clip_fps[clip];
	float clip_length = float(frames - 1) / fps;
	// CharacterRig.pose()'s rule: a loop wraps, a one-shot holds its ends.
	float at = (clip_loops[clip] != 0 ? mod(age, clip_length) : clamp(age, 0.0, clip_length)) * fps;
	int frame = min(int(floor(at)), frames - 2);
	float blend = at - float(frame);
	int row = clip_first[clip] + frame;
	vec4 r0 = vec4(0.0);
	vec4 r1 = vec4(0.0);
	vec4 r2 = vec4(0.0);
	for (int k = 0; k < 4; k++) {
		if (CUSTOM1[k] > 0.0) {
			add_bone(int(CUSTOM0[k] + 0.5), CUSTOM1[k], row, blend, r0, r1, r2);
		}
	}
	vec4 point = vec4(VERTEX, 1.0);
	VERTEX = vec3(dot(r0, point), dot(r1, point), dot(r2, point));
	NORMAL = normalize(vec3(dot(r0.xyz, NORMAL), dot(r1.xyz, NORMAL), dot(r2.xyz, NORMAL)));
	if (clip == death_clip) {
		VERTEX.y -= sink_depth * clamp((INSTANCE_CUSTOM.y - sink_from) / (sink_until - sink_from), 0.0, 1.0);
	}
	flash = INSTANCE_CUSTOM.z < flash_s ? 1.0 : 0.0;
}

void fragment() {
	float eye = COLOR.r;
	ALBEDO = mix(texture(palette, UV).rgb, eye_color, eye);
	ROUGHNESS = roughness;
	EMISSION = eye_color * eye_energy * eye + flash_color * flash;
}
