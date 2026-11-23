shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Black trim of the public car body, by body-local position (the car faces
// -Z, y up): a honeycomb mesh across the front intakes, carbon-fibre twill on
// the front splitter and rear diffuser, satin plastic elsewhere. Both
// patterns fade to their average before their cells are smaller than a pixel.
// Colours here are linear (the old trim's sRGB 0.05 is about 0.004 linear).
uniform float nose_z = -1.85;
uniform float tail_z = 1.8;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

// Distance to the nearest hexagon edge for a hex grid of cell size s.
float hex_edge(vec2 p, float s) {
	p /= s;
	const vec2 k = vec2(1.0, 1.7320508);
	vec2 a = mod(p, k) - k * 0.5;
	vec2 b = mod(p - k * 0.5, k) - k * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	g = abs(g);
	return 0.5 - max(dot(g, normalize(k)), g.x);
}

void fragment() {
	vec3 col = vec3(0.0045, 0.0048, 0.0053);
	float rough = 0.62;
	float metal = 0.0;
	float cc = 0.0;
	// Front intakes: honeycomb mesh on forward-facing trim low in the nose.
	float grille = step(lp.z, nose_z) * step(lp.y, 0.6) * smoothstep(-0.3, -0.6, ln.z);
	if (grille > 0.0) {
		float e = hex_edge(lp.xy, 0.034);
		float w = max(fwidth(e), 1e-4);
		float frame = 1.0 - smoothstep(0.09, 0.09 + w * 1.5, e);
		float resolve = 1.0 - smoothstep(0.08, 0.25, w);
		float hole = mix(0.55, 1.0 - frame, resolve);
		vec3 mesh = mix(vec3(0.012, 0.0125, 0.013), vec3(0.0008), hole);
		col = mix(col, mesh, grille);
		rough = mix(rough, mix(0.4, 0.95, hole), grille);
	}
	// Splitter and diffuser: clear-coated 2x2 twill carbon.
	float carbon = step(lp.y, 0.24) * max(step(lp.z, nose_z), step(tail_z, lp.z));
	if (carbon > 0.0) {
		vec2 uv = (abs(ln.y) > 0.6 ? lp.xz : lp.xy) / 0.006;
		vec2 cell = floor(uv);
		float twill = mod(cell.x + floor(cell.y * 0.5) * 2.0 + cell.y, 4.0) < 2.0 ? 1.0 : 0.0;
		vec2 f = fract(uv);
		float fibre = twill > 0.5 ? f.x : f.y;
		float sheen = 0.5 + 0.5 * sin(fibre * 3.14159);
		float resolve = 1.0 - smoothstep(0.35, 0.9, max(fwidth(uv.x), fwidth(uv.y)));
		float tone = mix(0.5, mix(0.35, 1.0, sheen) * mix(0.75, 1.0, twill), resolve);
		col = mix(col, vec3(0.006, 0.0062, 0.0068) * (0.5 + 1.1 * tone), carbon);
		rough = mix(rough, 0.38, carbon);
		cc = mix(cc, 0.8, carbon);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.08;
}
