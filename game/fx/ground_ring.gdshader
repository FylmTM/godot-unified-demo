// A ring drawn flat on the floor, on a quad lying at the floor (its UV the floor's square under it): the downed hero's
// revive ring (game/views/hero.tscn) and where a Mage's fireball would land (game/views/fireball_target.tscn). The
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

void fragment() {
	vec2 from_centre = UV * 2.0 - 1.0;
	float radius = length(from_centre);
	float soft = fwidth(radius);
	float band = smoothstep(inner - soft, inner, radius) * (1.0 - smoothstep(outer, outer + soft, radius));
	// the angle clockwise from up the screen (-V), as a share of a turn
	float turn = fract(atan(from_centre.x, -from_centre.y) / TAU + 1.0);
	float lit = turn <= fill ? 1.0 : dim;
	ALBEDO = color.rgb;
	ALPHA = color.a * band * lit;
}
