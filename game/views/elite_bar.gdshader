// An elite's health bar (game/views/elite.tscn): a flat quad that always faces the camera, drawn unlit, its fill the
// view's per-instance `fraction` of health (EliteView sets it), so every elite shares one material.
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled, fog_disabled;

// The health left, 0 to 1 (EliteView, from its data's hp of hp_max).
instance uniform float fraction : hint_range(0.0, 1.0) = 1.0;
uniform vec3 fill_color : source_color = vec3(0.85, 0.16, 0.1);
uniform vec3 empty_color : source_color = vec3(0.12, 0.05, 0.04);
uniform vec3 rim_color : source_color = vec3(0.03, 0.02, 0.02);
// The rim's width across and along the bar, in UV.
uniform vec2 rim = vec2(0.02, 0.18);

void vertex() {
	// a billboard: the camera's axes at the quad's place (its scale ignored)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	bool edge = UV.x < rim.x || UV.x > 1.0 - rim.x || UV.y < rim.y || UV.y > 1.0 - rim.y;
	float along = (UV.x - rim.x) / (1.0 - 2.0 * rim.x);
	ALBEDO = edge ? rim_color : (along <= fraction ? fill_color : empty_color);
}
