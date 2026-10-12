// Fog of war for the player's vision (DESIGN.md §13.6). Drawn on a full-screen quad after the scene:
// rebuilds each pixel's world position from the depth buffer, then looks it up in two masks drawn over
// the level from above: what's visible right now (red; green where the flashlight beam is) and what's
// been seen before (red). Visible: unchanged. Seen before: dim and nearly grey ("memory"). Never seen:
// almost black. Dark rooms look darker unless the flashlight lights them.
shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D visible_mask : filter_linear, repeat_disable;
uniform sampler2D memory_mask : filter_linear, repeat_disable;
// Flat area the masks cover: x, z of the corner, then width, depth.
uniform vec4 bounds = vec4(-32.0, -32.0, 64.0, 64.0);
uniform float memory_brightness = 0.3;
uniform float memory_saturation = 0.15;
uniform float unseen_brightness = 0.03;
uniform vec3 memory_tint = vec3(0.85, 0.9, 1.0);
// Up to 8 dark rooms: flat rectangles (x, z, width, depth) and how dark they look.
uniform int dark_zone_count = 0;
uniform vec4 dark_zones[8];
uniform float dark_room_shading = 0.6;

void vertex() {
	// Cover the whole screen whatever the camera does.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	float depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	world.xyz /= world.w;
	vec2 uv = (world.xz - bounds.xy) / bounds.zw;
	// Pixels with nothing behind them (beyond the level's edge) rebuild to a point far off along the
	// view ray: treat anything well below or above the level as never seen.
	bool inside = uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0 && world.y > -3.0 && world.y < 60.0;
	vec4 now = inside ? texture(visible_mask, uv) : vec4(0.0);
	float visible = now.r;
	float flashlight = now.g;
	float seen = inside ? texture(memory_mask, uv).r : 0.0;

	float shade = 1.0;
	for (int i = 0; i < dark_zone_count; i++) {
		vec4 zone = dark_zones[i];
		if (world.x >= zone.x && world.x <= zone.x + zone.z && world.z >= zone.y && world.z <= zone.y + zone.w) {
			shade = mix(1.0 - dark_room_shading, 1.0, flashlight);
		}
	}
	vec3 lit = color * shade;
	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	vec3 memory = mix(vec3(grey), color, memory_saturation) * memory_brightness * memory_tint * shade;
	vec3 hidden = mix(color * unseen_brightness, memory, seen);
	if (shade < 0.999) {
		ALBEDO = mix(hidden, lit, visible);
		ALPHA = 1.0;
	} else {
		// Blend instead of replacing, so effects drawn after the screen copy (muzzle flashes) survive
		// where you can see.
		ALBEDO = hidden;
		ALPHA = 1.0 - visible;
	}
}
