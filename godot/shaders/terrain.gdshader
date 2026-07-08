shader_type spatial;
// cull_disabled guarantees the tile faces are always visible regardless of
// triangle winding (prevents "hollow frame" tiles across renderers).
render_mode cull_disabled;

// Stylized terrain shader for the hex tiles. One shader, driven by uniforms,
// covers every tile type. Pure procedural noise — no textures, no screen or
// depth sampling — so it runs on BOTH Forward+ and Compatibility (GLES3).
//
// pattern_type:
//   0 = grass / pasture / field  (soft patchy noise + fine blade stipple)
//   1 = rock / ore               (hardened noise + bright mineral speckles)
//   2 = sand / desert            (long wavy dunes + fine grain)
//   3 = brick                    (running-bond brick courses with mortar)
//   4 = wheat                    (wind-bent crop furrows)
//
// The emboss term lights the pattern from a fixed local direction, which makes
// the surface read as gentle relief ("texture") without needing tangents.

uniform vec3 color_a : source_color = vec3(0.18, 0.42, 0.20);
uniform vec3 color_b : source_color = vec3(0.40, 0.66, 0.30);
uniform float rough_a = 0.92;
uniform float rough_b = 0.7;
uniform float metallic_amt = 0.0;
uniform float noise_scale = 6.0;
uniform int pattern_type = 0;
uniform float hex_radius = 1.3;
uniform float edge_darken = 0.30;   // strength of the inner border shadow
uniform float rim_strength = 0.18;  // strength of the edge rim light
uniform float bump_strength = 0.35; // strength of the emboss relief shading

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

// Height field for the active pattern; sampled at offsets for emboss shading.
float pattern_h(vec2 uv) {
	float n;
	if (pattern_type == 2) {
		// Desert: long slow dunes with a whisper of fine grain.
		float dunes = 0.5 + 0.5 * sin(uv.x * 0.5 + fbm(uv * 0.4) * 4.0);
		n = mix(dunes, fbm(uv), 0.35);
		n += (vnoise(uv * 7.0) - 0.5) * 0.08;
	} else if (pattern_type == 3) {
		// Brick: running-bond courses. Mortar seams read light, faces vary tone.
		vec2 buv = uv * vec2(0.55, 1.35);
		float row = floor(buv.y);
		buv.x += mod(row, 2.0) * 0.5;
		vec2 cell = fract(buv);
		float inside = smoothstep(0.0, 0.07, cell.x) * smoothstep(1.0, 0.93, cell.x)
			* smoothstep(0.0, 0.13, cell.y) * smoothstep(1.0, 0.87, cell.y);
		float face = 0.18 + 0.42 * hash12(vec2(floor(buv.x), row)) + 0.12 * fbm(uv * 2.0);
		n = mix(0.95, face, inside);
	} else if (pattern_type == 4) {
		// Wheat: wind-bent crop furrows with patchy ripeness.
		float furrows = 0.5 + 0.5 * sin(uv.y * 5.0 + fbm(uv * 0.9) * 3.0 + uv.x * 0.4);
		n = mix(furrows, fbm(uv * 1.6), 0.30);
	} else {
		n = fbm(uv);
		if (pattern_type == 1) {
			// Rock: harden the noise, then salt in bright mineral speckles.
			n = pow(clamp(n, 0.0, 1.0), 1.7);
			n += step(0.93, vnoise(uv * 9.0)) * 0.35;
		} else {
			// Grass: soft patches broken up by fine blade stipple.
			n = mix(n, vnoise(uv * 6.0), 0.22);
		}
	}
	return clamp(n, 0.0, 1.0);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 uv = v_local.xz * noise_scale;
	float n = pattern_h(uv);
	vec3 col = mix(color_a, color_b, n);

	// Emboss relief: light the height field from a fixed local direction so the
	// pattern reads as gentle 3D texture, not just painted color.
	float hx = pattern_h(uv + vec2(0.14, 0.0));
	float hy = pattern_h(uv + vec2(0.0, 0.14));
	float shade = 1.0 + (dot(vec2(hx - n, hy - n), vec2(-0.62, -0.78))) * bump_strength * 2.6;
	col *= clamp(shade, 0.72, 1.22);

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
