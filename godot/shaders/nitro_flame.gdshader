shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, fog_disabled;

// UV.x wraps the nozzle, UV.y follows the jet. Red selects the inner cone.
varying float clock_offset;
void vertex() {
	clock_offset = fract(dot(MODEL_MATRIX[3].xz, vec2(0.017, 0.023))) * 2.0;
	float t = TIME * 28.0 + clock_offset;
	VERTEX.z *= 0.93 + 0.07 * sin(t);
	VERTEX.xy += UV.y * UV.y * 0.024 * vec2(sin(t + 5.0 * UV.y), cos(t * 1.3));
}

void fragment() {
	float t = TIME * 14.0 + clock_offset;
	float azimuth = TAU * UV.x;
	float flow = sin(azimuth * 3.0 + UV.y * 11.0 - t);
	float eddy = sin(azimuth * 5.0 - UV.y * 17.0 + t * 1.7 + flow);
	float heat = 1.0 - UV.y;
	float erosion = smoothstep(-0.05, 0.32, heat + 0.14 * flow + 0.12 * eddy);
	vec3 sheath = mix(vec3(0.025, 0.12, 1.0), vec3(0.035, 0.9, 1.0), heat * heat);
	ALBEDO = mix(sheath, vec3(1.9, 2.0, 2.0), COLOR.r) * (1.2 + 0.13 * eddy);
	ALPHA = erosion * (0.28 + 0.51 * heat + 0.16 * COLOR.r);
}
