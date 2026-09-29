// Soft glowing sparkle above a resource found by sniffing: a camera-facing disc with a bright
// core and a gentle pulse. Unshaded and fog-free so it reads at a distance; alpha fades it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float pulse_hz = 1.2;

void vertex() {
	// Billboard: keep the quad facing the camera, scaled by the model matrix.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float glow = smoothstep(1.0, 0.0, r);
	float core = smoothstep(0.35, 0.0, r);
	float pulse = 0.75 + 0.25 * sin(TIME * TAU * pulse_hz);
	ALBEDO = color.rgb * (glow * 0.6 + core) * pulse;
	ALPHA = alpha * glow;
}
