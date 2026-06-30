shader_type spatial;
// cull_disabled guarantees the tile faces are always visible regardless of
// triangle winding (prevents "hollow frame" tiles across renderers).
render_mode cull_disabled;

// Stylized terrain shader for the hex tiles. One shader, driven by uniforms,
// covers grass/forest/pasture/field (pattern 0), rock/brick/ore (pattern 1),
// and desert dunes (pattern 2). Pure procedural noise — no textures, no screen
// or depth sampling — so it runs on BOTH Forward+ and the Compatibility (GLES3)
// renderer.
//
// Tactile detail: a soft inner-shadow toward the hex border (fake bevel AO) and
// a view-dependent fresnel rim light that catches the light as the camera pans.

uniform vec3 color_a : source_color = vec3(0.18, 0.42, 0.20);
uniform vec3 color_b : source_color = vec3(0.40, 0.66, 0.30);
uniform float rough_a = 0.92;
uniform float rough_b = 0.7;
uniform float metallic_amt = 0.0;
uniform float noise_scale = 6.0;
uniform int pattern_type = 0;   // 0 = grass, 1 = rock, 2 = sand
uniform float hex_radius = 1.3;
uniform float edge_darken = 0.30;   // strength of the inner border shadow
uniform float rim_strength = 0.18;  // strength of the edge rim light

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
		float dunes = 0.5 + 0.5 * sin(uv.x * 0.5 + fbm(uv * 0.4) * 4.0);
		n = mix(dunes, fbm(uv), 0.35);
	} else {
		n = fbm(uv);
		if (pattern_type == 1) {
			n = pow(clamp(n, 0.0, 1.0), 1.7);
		}
	}
	n = clamp(n, 0.0, 1.0);
	vec3 col = mix(color_a, color_b, n);

	// Inner-border shadow (fake bevel ambient occlusion toward the tile edge).
	float dist = length(v_local.xz);
	float edge = smoothstep(hex_radius * 0.68, hex_radius * 1.0, dist);
	col *= mix(1.0, 1.0 - edge_darken, edge);

	ALBEDO = col;
	ROUGHNESS = mix(rough_a, rough_b, n);
	METALLIC = metallic_amt;

	// View-dependent rim light so edges gleam as the camera pans.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += vec3(1.0) * fres * rim_strength;
}
