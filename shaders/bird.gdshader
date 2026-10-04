// Songbird of the bird flocks: flaps or tucks its wings from per-instance data, so animating
// a whole flock costs no CPU. INSTANCE_CUSTOM.x = flap amount (0 perched, wings tucked flat
// against the body … 1 flying), INSTANCE_CUSTOM.y = phase; the instance colour tints the
// plumage.
shader_type spatial;
render_mode cull_disabled;

uniform float flap_rate = 22.0;
uniform float flap_angle = 0.95;
uniform float tuck = 0.12;
uniform vec2 shoulder = vec2(0.025, 0.08);

void vertex() {
	if (abs(UV.x) > 0.001) {
		float side = sign(UV.x);
		float flap = INSTANCE_CUSTOM.x;
		vec3 pivot = vec3(shoulder.x * side, shoulder.y, VERTEX.z);
		vec3 rel = VERTEX - pivot;
		// Flying: the wing swings up and down around the body axis.
		float angle = sin(TIME * flap_rate + INSTANCE_CUSTOM.y) * flap_angle * side;
		float c = cos(angle);
		float s = sin(angle);
		vec3 flapping = vec3(rel.x * c - rel.y * s, rel.x * s + rel.y * c, rel.z);
		// Perched: the wing is tucked flat against the body's side.
		vec3 tucked = vec3(rel.x * tuck, rel.y - 0.005, rel.z);
		VERTEX = pivot + mix(tucked, flapping, flap);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
}
