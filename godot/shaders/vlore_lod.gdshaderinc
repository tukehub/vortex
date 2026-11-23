// Complementary opaque coverage keeps the full OSM silhouette throughout
// the handoff. Hardware visibility ranges cull entire chunks outside it.
float screen_threshold(vec2 pixel) {
	return fract(52.9829189 * fract(dot(floor(pixel), vec2(.06711056, .00583715))));
}

float skyline_coverage(float metres) {
	return smoothstep(460., 540., metres);
}
