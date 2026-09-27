// World-space XZ grid for debug floors: thin minor lines and stronger major lines,
// anti-aliased with fwidth() so they stay crisp at any distance or resolution.
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.42, 0.52, 0.38);
uniform vec3 line_color : source_color = vec3(0.24, 0.30, 0.22);
uniform float minor_spacing = 1.0;
uniform float major_spacing = 10.0;
uniform float minor_strength : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_position;

float grid_line(vec2 position, float spacing) {
	vec2 cell = position / spacing;
	vec2 distance_px = abs(fract(cell - 0.5) - 0.5) / fwidth(cell);
	return 1.0 - min(min(distance_px.x, distance_px.y), 1.0);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float minor = grid_line(world_position.xz, minor_spacing) * minor_strength;
	float major = grid_line(world_position.xz, major_spacing);
	ALBEDO = mix(base_color, line_color, max(minor, major));
	ROUGHNESS = 0.95;
}
