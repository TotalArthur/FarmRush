shader_type spatial;

// Player-coloured roof material. The base albedo is the owning player's
// colour; shingle-course banding plus noise tone/roughness breakup keep it
// reading as a tiled surface instead of a flat plastic block (the failure
// mode the old full-mesh tint had). Emission is driven by a uniform so
// GDScript can gate the Forward+ bloom boost behind the RenderingDevice
// check and leave it at 0.0 on GL.

uniform vec3 base_color : source_color = vec3(0.8, 0.3, 0.2);
uniform float emission_strength = 0.0;

varying vec3 v_local;

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
	v_local = VERTEX;
}

void fragment() {
	// Shingle courses: thin darkened seams stacked up the roof height.
	float course = fract(v_local.y * 26.0 + vnoise(v_local.xz * 30.0) * 0.35);
	float seam = smoothstep(0.22, 0.0, course) * 0.14;
	// Per-tile tone breakup so adjacent shingles vary slightly.
	float n = vnoise(v_local.xz * 46.0 + floor(v_local.y * 26.0) * 7.31);
	vec3 col = base_color * (1.0 - seam) * (0.90 + 0.18 * n);
	ALBEDO = col;
	// Satin base (matches the accent spec ~0.35) with per-shingle variation.
	ROUGHNESS = 0.48 - 0.22 * n;
	METALLIC = 0.05;
	EMISSION = base_color * emission_strength * (0.85 + 0.30 * n);
}
