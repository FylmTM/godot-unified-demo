// A Warrior's guard glint (game/views/elite.tscn): drawn over its shield while the shield is up, a warm light added on
// top that brightens and fades on the view's per-instance `glint` (EliteView sets it from the shown game time), so a
// rollback or a replay seek shows the same glint.
shader_type spatial;
render_mode unshaded, blend_add, shadows_disabled, depth_draw_never, fog_disabled;

// How bright the glint is now, 0 to 1.
instance uniform float glint : hint_range(0.0, 1.0) = 0.0;
uniform vec3 color : source_color = vec3(1.0, 0.82, 0.45);

void fragment() {
	ALBEDO = color * glint;
}
