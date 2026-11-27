// A wall cut away (game/play/cutaway.gd): the dungeon kit's look (game/materials/dungeon.tres: its palette atlas,
// matte) with a share of its pixels dropped in a 4×4 ordered dither, so a hero behind the wall shows through it while
// the wall still reads as a wall. `cut` is a per-instance uniform (the share dropped, 0 to 1), so every wall being cut
// shares this one material. It stays opaque: no sorting, no transparency, and its shadow stays whole (the shadow pass
// drops nothing), so the room's light doesn't change as a wall fades.
shader_type spatial;

// The kit's palette atlas and roughness (dungeon.tres's).
uniform sampler2D atlas: source_color, filter_linear, repeat_enable;
uniform float roughness: hint_range(0.0, 1.0) = 0.8;
// The share of the wall's pixels dropped.
instance uniform float cut: hint_range(0.0, 1.0) = 0.0;

// A 4×4 Bayer matrix: each pixel's threshold, in sixteenths.
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	if (!IN_SHADOW_PASS) {
		ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
		if ((BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0 < cut) {
			discard;
		}
	}
	ALBEDO = texture(atlas, UV).rgb;
	ROUGHNESS = roughness;
}
