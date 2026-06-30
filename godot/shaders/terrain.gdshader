shader_type spatial;
// cull_disabled guarantees the tile faces are always visible regardless of
// triangle winding (prevents "hollow frame" tiles across renderers).
render_mode specular_disabled, cull_disabled;

// Stylized terrain shader for the hex tiles. One shader, driven by uniforms,
// covers grass/forest/pasture/field (pattern 0), rock/brick/ore (pattern 1),
// and desert dunes (pattern 2). Pure procedural noise — no textures, no screen
// or depth sampling — so it runs on BOTH Forward+ and the Compatibility (GLES3)
// renderer.

uniform vec3 color_a : source_color = vec3(0.18, 0.42, 0.20);
uniform vec3 color_b : source_color = vec3(0.40, 0.66, 0.30);
uniform float rough_a = 0.92;
uniform float rough_b = 0.7;
uniform float noise_scale = 6.0;
uniform int pattern_type = 0; // 0 = grass, 1 = rock, 2 = sand

varying vec3 v_local;

// --- cheap value noise + fbm -----------------------------------------------
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

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.02;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 uv = v_local.xz * noise_scale;
	float n;
	if (pattern_type == 2) {
		// Desert: long wavy dunes plus a little break-up noise.
		float dunes = 0.5 + 0.5 * sin(uv.x * 0.5 + fbm(uv * 0.4) * 4.0);
		n = mix(dunes, fbm(uv), 0.35);
	} else {
		n = fbm(uv);
		if (pattern_type == 1) {
			// Rock/ore/brick: punchier contrast so it reads as stone.
			n = pow(clamp(n, 0.0, 1.0), 1.7);
		}
	}
	n = clamp(n, 0.0, 1.0);
	ALBEDO = mix(color_a, color_b, n);
	ROUGHNESS = mix(rough_a, rough_b, n);
}
