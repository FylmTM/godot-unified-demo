// The boss's ward (game/views/elite.tscn's Ward): a pale shell round the Bone King while no blow can hurt it, bright at
// its rim where the eye looks across it and clear in its middle, so the King shows through. `strength` is a
// per-instance uniform the view sets from the session's shown time (its slow pulse), so a rollback or a replay seek
// shows the ward as the state has it. Unshaded and additive: it gives light, as magic does (docs/ART.md, The look).
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// The ward's colour, and how sharply its rim falls off toward its middle.
uniform vec4 color: source_color = vec4(0.45, 0.75, 1.0, 1.0);
uniform float rim_power: hint_range(0.5, 8.0) = 2.5;
// How bright it burns now (0: unseen).
instance uniform float strength: hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	ALBEDO = color.rgb * rim * strength;
}
