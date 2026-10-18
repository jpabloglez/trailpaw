// Water v1: translucent tinted surface with gentle scrolling ripples in absolute world space
// (world_origin_offset keeps them steady across floating-origin rebases). No depth texture,
// so it works identically in Forward+ and Compatibility.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

global uniform vec3 world_origin_offset;

uniform vec3 shallow_color : source_color = vec3(0.30, 0.55, 0.60);
uniform vec3 deep_color : source_color = vec3(0.10, 0.28, 0.38);
uniform float opacity : hint_range(0.0, 1.0) = 0.78;
// Opacity at grazing angles (fresnel-like); below 1 so shallow beds show even far away.
uniform float grazing_opacity : hint_range(0.0, 1.0) = 0.85;
uniform sampler2D ripple_noise : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_scale : hint_range(0.001, 1.0) = 0.08;
uniform float ripple_speed : hint_range(0.0, 1.0) = 0.03;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.08;
// Per water plane (its chunk's biome, Phase 19): how clear the water is (0 the usual murky
// water … 1 crystal) and the colour clear water takes (linear RGB).
instance uniform float clarity = 0.0;
instance uniform vec3 clear_tint = vec3(0.03, 0.4, 0.38);

varying vec3 absolute_position;

void vertex() {
	absolute_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + world_origin_offset;
}

void fragment() {
	vec2 uv = absolute_position.xz * ripple_scale;
	vec3 n1 = texture(ripple_noise, uv + vec2(TIME * ripple_speed, 0.0)).rgb;
	vec3 n2 = texture(ripple_noise, uv * 1.7 - vec2(0.0, TIME * ripple_speed * 1.3)).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), (n1 + n2) * 0.5, ripple_strength);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 shallow = mix(shallow_color, clear_tint * 1.25, clarity);
	vec3 deep = mix(deep_color, clear_tint * 0.7, clarity);
	ALBEDO = mix(shallow, deep, facing);
	// More opaque at grazing angles; clear water lets the bed show through when looking down.
	ALPHA = mix(grazing_opacity, opacity * (1.0 - 0.45 * clarity), facing);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.5;
}
