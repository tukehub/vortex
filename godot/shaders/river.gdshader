shader_type spatial;
// A river ribbon (city_river.gd): opaque GGX water that takes the sky and
// probes like the sea, its ripples carried downstream. UV.x is metres across
// from the centre, UV.y metres along the flow; COLOR.r is 1 mid-channel and 0
// at the banks, COLOR.gb the flow direction in xz (0..1 encoded).
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.045, 0.16, 0.14);
uniform vec3 shallow_color : source_color = vec3(0.21, 0.36, 0.29);
uniform vec3 silt_color : source_color = vec3(0.42, 0.44, 0.36);
uniform vec3 foam_color : source_color = vec3(0.82, 0.86, 0.84);
uniform float flow_speed = 0.9;      // metres per second
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
// Ripples from CC0 wave heightmaps (tools/build_wave_normals.py), carried
// downstream in the frame of the current.
uniform sampler2D wave_nor : filter_linear_mipmap, repeat_enable;
uniform bool use_waves = false;

varying vec3 wpos;
varying vec2 flow;
varying float mid;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = normalize(COLOR.gb * 2.0 - 1.0 + vec2(1e-4));
	mid = COLOR.r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Gradient of value noise by central differences.
vec2 grad(vec2 p) {
	float e = 0.08;
	return vec2(vnoise(p + vec2(e, 0.0)) - vnoise(p - vec2(e, 0.0)), vnoise(p + vec2(0.0, e)) - vnoise(p - vec2(0.0, e))) / (2.0 * e);
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near_w = 1.0 - smoothstep(30.0, 260.0, dist);
	float mid_w = 1.0 - smoothstep(120.0, 900.0, dist);
	// Ripples in the frame of the current: stretched along it, carried down.
	vec2 side = vec2(-flow.y, flow.x);
	vec2 q = vec2(dot(wpos.xz, side), dot(wpos.xz, flow));
	float t = TIME * flow_speed;
	vec2 g = vec2(0.0);
	g += grad(vec2(q.x * 0.22, (q.y - t) * 0.09)) * 0.10 * mid_w;
	g += grad(vec2(q.x * 0.55 + 3.1, (q.y - t * 1.3) * 0.30)) * 0.05 * near_w;
	g += grad(vec2(q.x * 1.6 - 7.0, (q.y - t * 1.6) * 0.9)) * 0.012 * near_w;
	if (use_waves) {
		vec2 r = texture(wave_nor, vec2(q.x, q.y - t) / 13.0).rg * 2.0 - 1.0;
		vec2 r2 = texture(wave_nor, vec2(q.x * 1.7 + 0.37, q.y * 0.8 - t * 1.4) / 5.5).rg * 2.0 - 1.0;
		g += (r * 0.09 * mid_w + r2 * 0.05 * near_w);
	}
	// Slack water near the banks is calmer; riffles where the bed shallows.
	float edge = 1.0 - mid;
	g *= mix(1.0, 0.55, edge) * (1.0 + wetness * 0.8);
	vec2 slope = side * g.x + flow * g.y;
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	// Colour: green depth mid-channel, shallow silt-green over the gravel.
	float depth = smoothstep(0.0, 0.75, mid);
	vec3 water = mix(mix(silt_color, shallow_color, smoothstep(0.0, 0.35, mid)), deep_color, depth);
	float streak = vnoise(vec2(q.x * 0.9, (q.y - t * 1.4) * 0.12));
	float foam = smoothstep(0.82, 0.98, streak) * smoothstep(0.55, 0.0, mid) * near_w * 0.55;
	ALBEDO = mix(water, foam_color, foam) * (1.0 - night * 0.35);
	ROUGHNESS = mix(0.16, 0.26, smoothstep(250.0, 2200.0, dist)) + foam * 0.4 + night * 0.12;
	METALLIC = 0.0;
	// At night the lit town and sky glow would read as sand: dim the sheen.
	SPECULAR = 0.38 * (1.0 - night * 0.65);
}
