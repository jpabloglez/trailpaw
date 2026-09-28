// Foliage: model colour (copied from the imported material) plus wind sway. Sway grows with
// the square of the height above the model's base, so trunks and stems stay planted; the
// phase comes from the instance's absolute position (steady across floating-origin rebases),
// and the offset is applied along the world wind direction despite each instance's random yaw.
shader_type spatial;
render_mode cull_disabled;

global uniform vec3 world_origin_offset;
// xy = world wind direction (unit, XZ plane), z = strength (m), w = speed (rad/s).
global uniform vec4 wind;

uniform vec3 albedo : source_color = vec3(1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
// Per-type sway multiplier (0 = rigid).
uniform float sway = 0.0;
// Model height (model units) the sway is normalised by.
uniform float model_height = 1.0;

void vertex() {
	if (sway > 0.0) {
		vec3 instance_origin = MODEL_MATRIX[3].xyz + world_origin_offset;
		float phase = dot(instance_origin.xz, vec2(0.37, 0.23));
		float h = clamp(VERTEX.y / model_height, 0.0, 1.0);
		float gust = 0.65 + 0.35 * sin(TIME * wind.w + phase);
		float flutter = 0.15 * sin(TIME * wind.w * 2.7 + phase * 3.1);
		vec3 world_offset = vec3(wind.x, 0.0, wind.y) * wind.z * sway * h * h * (gust + flutter);
		VERTEX += inverse(mat3(MODEL_MATRIX)) * world_offset;
	}
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
}
