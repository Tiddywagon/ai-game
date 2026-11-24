shader_type spatial;
// A cosmetic skin on a 3D model (SkinLook.material()): the pattern in object space, from the side the
// surface faces (so boxes and spheres both take it), worn by `wear`. `silhouette` draws it flat black
// (a skin you don't own on the collection screen).

#include "res://assets/shaders/skin_pattern.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.5);
uniform vec3 accent_color : source_color = vec3(0.25);
uniform int pattern = 0;
uniform float pattern_scale = 1.0;
uniform float wear : hint_range(0.0, 1.0) = 0.0;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.2;
uniform bool silhouette = false;

varying vec3 object_position;
varying vec3 object_normal;

void vertex() {
	object_position = VERTEX;
	object_normal = NORMAL;
}

void fragment() {
	vec3 n = abs(object_normal);
	vec2 uv = n.x > n.y && n.x > n.z ? object_position.zy : (n.y > n.z ? object_position.xz : object_position.xy);
	float glow;
	vec3 color = skin_color(uv * 2.0, base_color, accent_color, pattern, pattern_scale, wear, glow);
	if (silhouette) {
		ALBEDO = vec3(0.03);
		ROUGHNESS = 1.0;
	} else {
		ALBEDO = color;
		METALLIC = pattern == 5 ? 0.55 : metallic_amount * (1.0 - wear);
		ROUGHNESS = 0.45 + wear * 0.45;
		EMISSION = accent_color * glow * 2.2;
	}
}
