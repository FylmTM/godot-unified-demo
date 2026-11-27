// A ring drawn flat on the floor, on a quad lying at the floor (its UV the floor's square under it): the downed hero's
// revive ring (game/views/hero.tscn), where a Mage's fireball would land (game/views/fireball_target.tscn) and the
// King's slam (game/views/elite.tscn: dashed, its waves crawling inward). The
// ring's arc from the top (up the screen, clockwise) to `fill` of a turn shows bright, the rest dim, so a ring can be a
// progress meter; `fill` is a per-instance uniform (GeometryInstance3D.set_instance_shader_parameter), so every view
// shares the material. Unshaded and below the glow's threshold: a marker, not a light (docs/ART.md, The look).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// The ring's colour where it is filled, and the share of it the unfilled arc keeps.
uniform vec4 color: source_color = vec4(0.95, 0.85, 0.62, 0.9);
uniform float dim: hint_range(0.0, 1.0) = 0.2;
// The ring's band, as radii of the quad's half width.
uniform float inner: hint_range(0.0, 1.0) = 0.86;
uniform float outer: hint_range(0.0, 1.0) = 0.95;
// How much of the ring, a turn from the top, shows bright (1: all of it).
instance uniform float fill: hint_range(0.0, 1.0) = 1.0;
// A danger's pattern, so a ring tells what it is by its shape, never its colour alone (docs/ART.md): `dashes` cuts the
// band into that many dashes (0: solid), and waves crawl inward across the disc inside it as the ring fills, `waves`
// of them from empty to full (0: none: a function of `fill`, the view's data, so a pause or a seek shows them still),
// `wave_alpha` of the colour's at their crest. The King's slam's ring has both; the revive's and the fireball's none.
uniform float dashes = 0.0;
uniform float waves = 0.0;
uniform float wave_alpha: hint_range(0.0, 1.0) = 0.35;
// The waves' spacing, across the disc's radius.
const float WAVE_COUNT = 4.0;

void fragment() {
	vec2 from_centre = UV * 2.0 - 1.0;
	float radius = length(from_centre);
	float soft = fwidth(radius);
	float band = smoothstep(inner - soft, inner, radius) * (1.0 - smoothstep(outer, outer + soft, radius));
	// the angle clockwise from up the screen (-V), as a share of a turn
	float turn = fract(atan(from_centre.x, -from_centre.y) / TAU + 1.0);
	float lit = turn <= fill ? 1.0 : dim;
	float dash = dashes > 0.0 ? step(0.5, fract(turn * dashes)) : 1.0;
	// sin(k r + w f): a crest's radius shrinks as the ring fills: the waves crawl inward
	float wave = waves > 0.0 ? pow(0.5 + 0.5 * sin(TAU * (radius * WAVE_COUNT + fill * waves)), 4.0) : 0.0;
	float inside = 1.0 - smoothstep(inner - soft, inner, radius);
	ALBEDO = color.rgb;
	ALPHA = color.a * max(band * lit * dash, inside * wave * wave_alpha * lit);
}
