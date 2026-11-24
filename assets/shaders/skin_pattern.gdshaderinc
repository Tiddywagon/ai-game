// A cosmetic skin's look (DESIGN.md §6.7, SkinLook): two colours drawn in one of seven patterns, then
// worn by its wear (0 Factory New ... 1 Battle-Scarred): scratches show the bare metal, the paint dulls
// and fades. Shared by skin.gdshader (3D models) and skin_swatch.gdshader (2D cards and icons).
// Patterns, in SkinTable.PATTERNS order: 0 solid, 1 camo, 2 stripes, 3 hex, 4 splatter, 5 gradient, 6 glow.

float skin_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float skin_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(skin_hash(i), skin_hash(i + vec2(1.0, 0.0)), u.x), mix(skin_hash(i + vec2(0.0, 1.0)), skin_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float skin_fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += skin_noise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}

// Distance to the nearest hex cell edge (0 on an edge).
float skin_hex_edge(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(dot(q, normalize(vec2(1.0, 1.7320508))), q.x);
}

// The colour at `uv` (pattern space: about one unit across the item), and how much of it glows (0-1).
vec3 skin_color(vec2 uv, vec3 base, vec3 accent, int pattern, float scale, float wear, out float glow) {
	vec2 p = uv * scale;
	glow = 0.0;
	vec3 color = base;
	if (pattern == 0) {
		color = mix(base, accent, smoothstep(0.62, 0.9, skin_fbm(p * 1.5)) * 0.25);
	} else if (pattern == 1) {
		float n = skin_fbm(p * 2.2);
		float m = skin_fbm(p * 2.2 + vec2(7.3, 2.1));
		color = n > 0.52 ? accent : base;
		color = m > 0.6 ? mix(base, accent, 0.5) * 0.85 : color;
	} else if (pattern == 2) {
		float s = sin((p.x + p.y * 0.45) * 14.0 + skin_noise(p * 3.0) * 1.5);
		color = mix(base, accent, smoothstep(-0.15, 0.15, s));
	} else if (pattern == 3) {
		float edge = skin_hex_edge(p * 5.0);
		float cell = skin_hash(floor(p * 5.0));
		color = mix(base * (0.88 + cell * 0.24), accent, 1.0 - smoothstep(0.03, 0.07, edge));
	} else if (pattern == 4) {
		float spots = 0.0;
		for (int i = 0; i < 3; i++) {
			vec2 q = p * (3.0 + float(i) * 2.5) + float(i) * 4.1;
			vec2 cell = floor(q);
			vec2 centre = vec2(skin_hash(cell), skin_hash(cell + 9.1));
			float radius = 0.12 + skin_hash(cell + 3.7) * 0.28;
			spots = max(spots, 1.0 - smoothstep(radius * 0.8, radius, length(fract(q) - centre) + skin_noise(q * 4.0) * 0.12));
		}
		color = mix(base, accent, spots);
	} else if (pattern == 5) {
		float t = clamp(uv.y * 0.9 + 0.5 + (skin_fbm(p * 1.2) - 0.5) * 0.3, 0.0, 1.0);
		color = mix(accent, base, t);
		color += vec3(0.12) * pow(max(sin((uv.x + uv.y) * 9.0), 0.0), 8.0);
	} else {
		float vein = abs(skin_fbm(p * 2.5) - 0.5);
		glow = 1.0 - smoothstep(0.015, 0.06, vein);
		color = mix(base, accent, glow);
	}
	// Wear: paint scratched off (bright bare metal), chipped edges, dulled and faded colour.
	float scratch = skin_noise(vec2(p.x * 1.5, p.y * 40.0) + skin_noise(p * 3.0) * 4.0);
	float chips = skin_fbm(p * 9.0 + 3.0);
	float worn = max(step(1.0 - wear * 0.22, scratch), step(1.0 - wear * 0.55, chips));
	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(grey), wear * 0.45) * (1.0 - wear * 0.25);
	color = mix(color, vec3(0.62, 0.62, 0.6), worn * 0.85);
	glow *= (1.0 - worn) * (1.0 - wear * 0.5);
	return color;
}
