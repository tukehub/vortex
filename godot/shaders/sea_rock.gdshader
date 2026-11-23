shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Limestone armour stones at the waterline (SeaRocks): ochre and brown by
// vertex colour; darker, glossier and a little green where the waves keep
// them wet, up to `splash` metres above the water. Rain wets them all over.
uniform float water_y = 0.0;
uniform float splash = 0.9;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying float wy;

void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float above = wy - water_y;
	float wet = 1.0 - smoothstep(0.05, splash, above);
	wet = max(wet, wetness * 0.8);
	// Vertex colours are sRGB; shading is linear.
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	// Algae just above the water, darker wet stone, dry crust above.
	col = mix(col, col * vec3(0.55, 0.6, 0.42), (1.0 - smoothstep(0.0, 0.25, above)) * step(-0.4, above) * 0.7);
	col *= mix(1.0, 0.5, wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.82, 0.28, wet);
	SPECULAR = mix(0.4, 0.6, wet);
}
