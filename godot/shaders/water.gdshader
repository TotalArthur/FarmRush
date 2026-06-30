shader_type spatial;
render_mode cull_back;

// Clean, calm, stylized tabletop water. Smooth deep-blue surface (#104E8B ->
// #1C86EE) with high roughness so it never produces harsh pixelated specular
// glints, plus a very gentle, slow, large-scale wave so it reads as a calm
// pond rather than a stormy sea. Works on both Forward+ and Compatibility.

uniform vec3 deep_color : source_color = vec3(0.063, 0.306, 0.545);    // #104E8B
uniform vec3 shallow_color : source_color = vec3(0.110, 0.525, 0.933); // #1C86EE
uniform float wave_amp = 0.025;
uniform float wave_scale = 0.30;   // large wavelength = calm
uniform float wave_speed = 0.20;   // slow

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
	float h = sin(world.x * wave_scale + t) + cos(world.z * wave_scale * 0.9 + t * 0.8);
	VERTEX.y += h * wave_amp * 0.5;
}

void fragment() {
	// Smooth, low-frequency colour variation only — no high-frequency noise.
	float t = TIME * wave_speed * 0.4;
	float n = vnoise(v_world * 0.10 + vec2(t, 0.0));
	vec3 col = mix(deep_color, shallow_color, smoothstep(0.35, 0.7, n) * 0.55);
	ALBEDO = col;
	ROUGHNESS = 0.7;
	METALLIC = 0.0;
}
