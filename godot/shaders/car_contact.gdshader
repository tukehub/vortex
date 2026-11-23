shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// Road contact under a car: a soft occlusion under the floor pan and, at each
// tyre, a dark contact patch inside a softer penumbra. The quad is
// `plane_size` metres; `tyres` are the wheels' (x, z) in car space.
uniform vec2 plane_size = vec2(2.3, 4.8);
uniform vec2 tyres[4];
uniform vec2 tyre_patch = vec2(0.13, 0.17);

void fragment() {
	vec2 m = (UV - 0.5) * plane_size;          // metres, x across, y along
	vec2 p = UV * 2.0 - 1.0;
	float body = 1.0 - smoothstep(0.2, 1.0, length(p * vec2(1.2, 0.9)));
	float core = 0.0;
	float penumbra = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 d = (m - tyres[i]) / tyre_patch;
		float l = length(d);
		core = max(core, 1.0 - smoothstep(0.55, 1.0, l));
		penumbra = max(penumbra, 1.0 - smoothstep(0.8, 2.6, l));
	}
	ALBEDO = vec3(0.01);
	ALPHA = max(body * 0.42, max(penumbra * 0.5, core * 0.82));
}
