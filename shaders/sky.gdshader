// Day/night sky (DayNightCycle): a gradient from the horizon to the zenith, a soft sun disk
// and glow, a small moon, stars that fade in at night and a cheap cloud cover (weather).
// Colours come from data/world/day_night.tres through the cycle; nothing is sampled per frame
// on the CPU.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.3, 0.52, 0.88);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.8, 0.88);
uniform vec3 ground_color : source_color = vec3(0.35, 0.38, 0.33);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(vec3(i, 0.0));
	float b = hash(vec3(i + vec2(1.0, 0.0), 0.0));
	float c = hash(vec3(i + vec2(0.0, 1.0), 0.0));
	float d = hash(vec3(i + vec2(1.0, 1.0), 0.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, -1.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.55));
	col = mix(col, ground_color, smoothstep(0.0, -0.08, up));
	// Stars: sparse points above the horizon at night.
	if (stars > 0.0 && up > 0.0) {
		vec3 cell = floor(dir * 180.0);
		float h = hash(cell);
		float star = step(0.9965, h) * smoothstep(0.0, 0.25, up);
		col += vec3(star * stars * (0.6 + 0.4 * hash(cell + 7.0)));
	}
	// Sun disk and glow, moon.
	float sun_dot = dot(dir, normalize(sun_direction));
	col += sun_color * (smoothstep(0.9990, 0.9996, sun_dot) * 3.0 + pow(max(sun_dot, 0.0), 24.0) * 0.35);
	float moon_dot = dot(dir, normalize(moon_direction));
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9993, 0.9997, moon_dot) * stars;
	// Clouds: soft noise on a dome, denser with cloud cover, tinted by the horizon light.
	if (cloud_cover > 0.0 && up > 0.02) {
		vec2 uv = dir.xz / (up + 0.15) * 1.6;
		float n = noise(uv) * 0.6 + noise(uv * 2.3) * 0.3 + noise(uv * 5.1) * 0.1;
		float c = smoothstep(1.0 - cloud_cover, 1.15 - cloud_cover * 0.6, n) * smoothstep(0.02, 0.2, up);
		vec3 cloud = mix(horizon_color, vec3(0.9), 0.5) * mix(1.0, 0.55, cloud_cover);
		col = mix(col, cloud, c * 0.9);
	}
	COLOR = col;
}
