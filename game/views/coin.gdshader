// The coins on the floor (game/views/coins.gd): one MultiMesh of KayKit's coin, each instance stood on its edge and
// spun about the vertical, hovering a hand above where it lies, so a coin reads as loot from the game's high camera
// (lying flat, as the model does, it would be a dot on the floor). It hops out of where it fell as it appears, bobs
// while it lies, and blinks through its last seconds before it goes. Matte on the dungeon pack's palette atlas, as
// game/materials/dungeon.tres draws the model; coins.gd sets every uniform from where it lives.
//
// INSTANCE_CUSTOM, the contract simulation/extension/frame.odin's loot_instance keeps:
// - x: the coin's value in gold: worth more, drawn bigger (up to most_gold).
// - y: the seconds since it fell. The extension writes the tick it fell; the loot kind's policy (MULTI_POLICY's ages)
//   has the host turn it into seconds at the shown time, so a pause holds the spin and a replay's seek shows the
//   moment the state says. A coin shows only once its drop is verified, so on a client it may appear a little into its
//   hop.
// - z, w: spare, 0.
shader_type spatial;

uniform sampler2D palette : source_color, filter_linear;
uniform float roughness = 0.8;
// A coin worth 1 drawn this many times the model's size, and this much bigger for each gold more, up to most_gold.
uniform float size = 1.6;
uniform float size_per_gold = 0.15;
uniform float most_gold = 5.0;
// How long a coin lies before it goes (the sim's LOOT_LIFE_S), and through how many of its last seconds it blinks,
// faster as it nears its end.
uniform float life = 30.0;
uniform float blink_s = 4.0;
// The hop out of where it fell: how long, and how high at its top (metres).
uniform float hop_s = 0.4;
uniform float hop_height = 0.8;
// Where it hovers at rest (its centre above the floor), its bob about there and the bob's rate (cycles a second).
uniform float hover = 0.45;
uniform float bob = 0.06;
uniform float bob_hz = 0.7;
// How fast it spins (turns a second).
uniform float spin_hz = 0.6;

void vertex() {
	float gold = INSTANCE_CUSTOM.x;
	float age = max(INSTANCE_CUSTOM.y, 0.0);
	float hop = clamp(age / hop_s, 0.0, 1.0);
	float scale = size * (1.0 + size_per_gold * (clamp(gold, 1.0, most_gold) - 1.0));
	scale *= smoothstep(0.0, 0.6, hop); // it grows out of the fallen as it leaves the floor
	float left = life - age;
	if (left < blink_s && fract(left * mix(5.0, 2.0, left / blink_s)) < 0.4) {
		scale = 0.0; // a blink: off for 40 % of each beat
	}
	// Stand the disc on its edge (the model lies flat, its faces up y: turn it a quarter about x), then spin it about y.
	float turn = TAU * spin_hz * age;
	mat3 stand = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, -1.0, 0.0));
	mat3 spin = mat3(vec3(cos(turn), 0.0, -sin(turn)), vec3(0.0, 1.0, 0.0), vec3(sin(turn), 0.0, cos(turn)));
	mat3 pose = spin * stand;
	float lift = hover * smoothstep(0.0, 1.0, hop) + hop_height * 4.0 * hop * (1.0 - hop);
	lift += bob * sin(TAU * bob_hz * age) * hop;
	VERTEX = pose * (VERTEX * scale) + vec3(0.0, lift, 0.0);
	NORMAL = pose * NORMAL;
}

void fragment() {
	ALBEDO = texture(palette, UV).rgb;
	ROUGHNESS = roughness;
}
