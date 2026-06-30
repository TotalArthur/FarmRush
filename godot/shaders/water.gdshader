shader_type spatial;
render_mode cull_back, specular_disabled;

// Stylized tabletop water: gentle TIME-driven wave displacement, a two-tone
// rippling surface, and an animated foam ring where the ocean meets the island
// shore. Works on both renderers.
//
// NOTE: the "textbook" foam uses DEPTH_TEXTURE to detect where geometry meets
// the water, but the Compatibility renderer has no depth prepass, so we use a
// shore-radius ring instead (the island is roughly circular). A depth-based
// version for Forward+ is included, commented, at the bottom of fragment().

uniform vec3 deep_color : source_color = vec3(0.05, 0.20, 0.38);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.42, 0.62);
uniform vec3 foam_color : source_color = vec3(0.90, 0.96, 1.0);
uniform float shore_radius = 9.0;
uniform float foam_width = 0.7;
uniform float wave_amp = 0.05;
uniform float wave_scale = 1.1;
uniform float wave_speed = 0.7;

varying vec2 v_world;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world = world.xz;
	float t = TIME * wave_speed;
	float h = sin(world.x * wave_scale + t) * 0.5
		+ cos(world.z * wave_scale * 0.8 + t * 1.1) * 0.5
		+ (vnoise(world.xz * 0.5 + vec2(t * 0.1)) - 0.5);
	VERTEX.y += h * wave_amp;
}

void fragment() {
	float t = TIME * 0.4;
	float ripple = vnoise(v_world * 0.8 + vec2(t, -t));
	vec3 col = mix(deep_color, shallow_color, ripple * 0.7);

	// Animated shore-foam ring.
	float d = length(v_world);
	float band = 1.0 - smoothstep(0.0, foam_width, abs(d - shore_radius));
	float sparkle = 0.55 + 0.45 * sin(d * 7.0 - TIME * 2.5 + ripple * 6.0);
	float foam = clamp(band * sparkle, 0.0, 1.0);
	col = mix(col, foam_color, foam);

	ALBEDO = col;
	ROUGHNESS = 0.22;
	METALLIC = 0.0;

	// --- Forward+ depth-based shoreline foam (uncomment when on Forward+) ----
	// float scene_depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	// vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	// vpos.xyz /= vpos.w;
	// float diff = VERTEX.z - vpos.z;
	// float edge = 1.0 - smoothstep(0.0, 0.4, diff);
	// col = mix(col, foam_color, edge);
}
