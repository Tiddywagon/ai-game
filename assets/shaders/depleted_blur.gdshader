shader_type canvas_item;
// Exhaustion and Dehydration (DESIGN.md §13.7): the view blurs, more toward the edges, and dims a
// little. `amount` 0 to 1 (the HUD hides the overlay at 0).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 from_centre = SCREEN_UV - vec2(0.5);
	float edge = clamp(length(from_centre) * 2.0, 0.0, 1.0);
	float radius = amount * mix(0.0015, 0.008, edge);
	vec3 sum = vec3(0.0);
	float total = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float weight = exp(-float(x * x + y * y) / 8.0);
			sum += texture(screen_texture, SCREEN_UV + vec2(float(x), float(y)) * radius).rgb * weight;
			total += weight;
		}
	}
	COLOR = vec4(sum / total * (1.0 - 0.2 * amount * edge), 1.0);
}
