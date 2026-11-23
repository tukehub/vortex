// The two overlapping LODs use complementary screen-space masks.
uniform float tree_clock = 0.0;
varying flat vec4 tree_data;

bool tree_culled(vec2 pixel) {
	if (tree_data.z < 0.5) {
		return false;
	}
	float age = mod(tree_clock - tree_data.w + 256.0, 256.0);
	float progress = smoothstep(0.0, 0.18, age);
	float threshold = fract(52.9829189 * fract(dot(floor(pixel), vec2(0.06711056, 0.00583715))));
	return tree_data.z < 1.5 ? threshold >= progress : threshold < progress;
}

vec3 tree_tint() {
	return mix(vec3(0.88, 0.96, 0.83), vec3(1.10, 1.04, 0.95), tree_data.y);
}
