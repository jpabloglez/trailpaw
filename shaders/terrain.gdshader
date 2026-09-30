// Terrain surface: biome ground palettes (per-vertex, blended on the CPU) varied by a
// world-space macro pattern, fine brightness detail, and rock on steep slopes.
// Distance fog comes from the Environment (applied by the engine to spatial shaders).
//
// COLOR.rgb           = biome palette colour A (sRGB)
// (UV2.xy, COLOR.a)   = biome palette colour B (sRGB). Packed into standard attributes
//                       because custom attributes are not read reliably by Compatibility.
// world_origin_offset (global) turns floating-origin local positions into absolute ones,
// so patterns stay put across rebases.
shader_type spatial;

global uniform vec3 world_origin_offset;
global uniform float water_level;
// Ground wetness from the weather (0 dry … 1 soaked): darker, glossier ground.
global uniform float wetness;

uniform sampler2D pattern_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
// Macro pattern mixing palette A and B (1 / wavelength in m).
uniform float macro_scale : hint_range(0.0005, 0.1) = 0.01;
// Palette A↔B transition sharpness around the pattern midpoint.
uniform float macro_contrast : hint_range(0.0, 0.5) = 0.18;
// Fine brightness variation.
uniform float detail_scale : hint_range(0.01, 2.0) = 0.21;
uniform float detail_strength : hint_range(0.0, 0.5) = 0.08;
// Rock tint on slopes between these angles (degrees from horizontal).
uniform vec3 rock_color : source_color = vec3(0.47, 0.44, 0.40);
uniform float rock_start_degrees : hint_range(0.0, 90.0) = 28.0;
uniform float rock_full_degrees : hint_range(0.0, 90.0) = 40.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
// Shore: wet sand/mud band just above the water line (m above water_level).
uniform vec3 shore_color : source_color = vec3(0.62, 0.56, 0.42);
uniform float shore_height : hint_range(0.0, 5.0) = 1.2;
// Underwater: the bed darkens and turns blue-green with depth (m below water_level),
// so shallow water reads light and deep water dark without a depth texture.
uniform vec3 underwater_color : source_color = vec3(0.10, 0.20, 0.22);
uniform float underwater_depth : hint_range(0.1, 20.0) = 4.0;

varying vec3 absolute_position;
varying vec3 world_normal;
varying vec3 palette_b;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	absolute_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + world_origin_offset;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	palette_b = vec3(UV2.x, UV2.y, COLOR.a);
}

void fragment() {
	float macro = texture(pattern_noise, absolute_position.xz * macro_scale).r;
	float mix_b = smoothstep(0.5 - macro_contrast, 0.5 + macro_contrast, macro);
	vec3 ground = mix(srgb_to_linear(COLOR.rgb), srgb_to_linear(palette_b), mix_b);
	float detail = texture(pattern_noise, absolute_position.xz * detail_scale).r - 0.5;
	ground *= 1.0 + detail * 2.0 * detail_strength;
	float slope_degrees = degrees(acos(clamp(world_normal.y, 0.0, 1.0)));
	float rock = smoothstep(rock_start_degrees, rock_full_degrees, slope_degrees);
	vec3 albedo = mix(ground, rock_color, rock);
	float height = absolute_position.y - water_level;
	float shore = 1.0 - smoothstep(0.0, shore_height, height);
	albedo = mix(albedo, shore_color, shore * (1.0 - rock));
	float depth = clamp(-height / underwater_depth, 0.0, 1.0);
	albedo = mix(albedo, underwater_color, depth);
	float wet = wetness * (1.0 - depth);
	ALBEDO = albedo * (1.0 - 0.35 * wet);
	ROUGHNESS = mix(roughness_value, 0.75, wet * (1.0 - rock * 0.5));
}
