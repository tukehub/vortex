shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Tyre of the public car, by wheel-local position: tread (r > ~0.38) with
// three circumferential grooves, sidewalls with a raised band. No lettering:
// the source's sidewall trademark was removed on import and stays removed.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float r = length(lp.yz);
	float tread = smoothstep(0.368, 0.385, r);
	float aa = max(fwidth(lp.x), 1e-4);
	float groove = 0.0;
	for (int i = -1; i <= 1; i++) {
		groove = max(groove, 1.0 - smoothstep(0.006, 0.006 + aa, abs(lp.x - float(i) * 0.052)));
	}
	groove *= tread;
	float side = 1.0 - tread;
	float band = smoothstep(0.316, 0.321, r) * (1.0 - smoothstep(0.343, 0.348, r));
	// Linear: weathered rubber, about sRGB 0.07.
	vec3 rubber = vec3(0.0058, 0.0058, 0.0062);
	vec3 col = rubber * mix(1.0, 1.12, side);
	col = mix(col, rubber * 1.6, band * side * 0.5);
	col *= 1.0 - groove * 0.65;
	float rough = mix(0.86, 0.78, side);
	rough = mix(rough, 0.96, groove);
	// A wet tyre darkens and its rubber picks up a sheen; grooves hold water
	// but stay dark.
	col *= 1.0 - 0.25 * wetness;
	rough = mix(rough, 0.32, wetness * (1.0 - groove));
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
