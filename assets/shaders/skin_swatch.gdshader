shader_type canvas_item;
// A cosmetic skin on a 2D card or item icon (SkinLook.swatch_material()): the pattern across the drawn
// shape, worn by `wear`; `silhouette` draws it as a dark shape (a skin you don't own).

#include "res://assets/shaders/skin_pattern.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.5);
uniform vec3 accent_color : source_color = vec3(0.25);
uniform int pattern = 0;
uniform float pattern_scale = 1.0;
uniform float wear : hint_range(0.0, 1.0) = 0.0;
uniform bool silhouette = false;

void fragment() {
	float glow;
	vec3 color = skin_color((UV - 0.5) * 2.0, base_color, accent_color, pattern, pattern_scale, wear, glow);
	vec4 drawn = COLOR;
	COLOR = silhouette ? vec4(vec3(0.17, 0.17, 0.18), drawn.a) : vec4(color + accent_color * glow * 0.6, drawn.a);
}
