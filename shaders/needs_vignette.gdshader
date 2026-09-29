// Soft edge tint hinting that a need is critical (ADR-003: a hint, never an alarm).
// An ellipse fitted to the screen (edges at 1, corners at ~1.41). Transparent at intensity 0; the edges darken and warm towards max_alpha at intensity 1.
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.25, 0.14, 0.06, 1.0);
uniform float max_alpha : hint_range(0.0, 1.0) = 0.45;
uniform float inner_radius : hint_range(0.0, 2.0) = 0.7;
uniform float outer_radius : hint_range(0.0, 2.0) = 1.45;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float edge = smoothstep(inner_radius, outer_radius, length(p));
	COLOR = vec4(tint.rgb, edge * max_alpha * intensity);
}
