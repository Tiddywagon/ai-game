shader_type spatial;
// High-contrast outline (Settings > Accessibility, DESIGN.md §17): draws the mesh's back faces,
// pushed out along the normals, in one flat colour. Used as a material overlay.
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform float width = 0.06;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
