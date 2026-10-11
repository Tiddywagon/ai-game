shader_type canvas_item;
// Screen-wide brightness, gamma and colorblind correction (Settings autoload, DESIGN.md §17).

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float brightness = 1.0;
uniform float gamma = 1.0;
// 0 off, 1 protanopia, 2 deuteranopia, 3 tritanopia.
uniform int colorblind_mode = 0;

// Daltonization: simulate what the viewer can't tell apart, then shift that lost difference into
// channels they can see.
vec3 daltonize(vec3 c, int mode) {
	float L = 17.8824 * c.r + 43.5161 * c.g + 4.11935 * c.b;
	float M = 3.45565 * c.r + 27.1554 * c.g + 3.86714 * c.b;
	float S = 0.0299566 * c.r + 0.184309 * c.g + 1.46709 * c.b;
	float l = L;
	float m = M;
	float s = S;
	if (mode == 1) {
		l = 2.02344 * M - 2.52581 * S;
	} else if (mode == 2) {
		m = 0.494207 * L + 1.24827 * S;
	} else {
		s = -0.395913 * L + 0.801109 * M;
	}
	vec3 seen = vec3(
		0.0809444479 * l - 0.130504409 * m + 0.116721066 * s,
		-0.0102485335 * l + 0.0540193266 * m - 0.113614708 * s,
		-0.000365296938 * l - 0.00412161469 * m + 0.693511405 * s);
	vec3 lost = c - seen;
	return clamp(c + vec3(0.0, 0.7 * lost.r + lost.g, 0.7 * lost.r + lost.b), 0.0, 1.0);
}

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	if (colorblind_mode > 0) {
		c = daltonize(c, colorblind_mode);
	}
	c = pow(max(c * brightness, vec3(0.0)), vec3(1.0 / gamma));
	COLOR = vec4(c, 1.0);
}
