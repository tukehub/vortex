shader_type spatial;
// The lion fountain's water (rrapi_fountain.gd). pool: the basin's surface,
// rings spreading from where the jet falls (local -Z of the centre) over
// still green water. Otherwise the jet: a tube whose UV.y runs from the
// mouth (0) to the water (1), streaks of white water carried down it.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform bool pool = true;
uniform vec3 deep : source_color = vec3(0.08, 0.24, 0.24);
uniform vec3 foam : source_color = vec3(0.86, 0.92, 0.93);

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	if (pool) {
		vec2 fall = vec2(0.0, -0.6);
		float r = length(lpos.xz - fall);
		float ring = sin(r * 9.0 - TIME * 6.0) * exp(-r * 0.7);
		vec2 dir = normalize(lpos.xz - fall + vec2(1e-4));
		vec3 n = normalize(vec3(-dir.x * ring * 0.18, 1.0, -dir.y * ring * 0.18));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		float froth = smoothstep(0.7, 0.0, r) * (0.55 + 0.45 * sin(TIME * 11.0 + r * 20.0));
		ALBEDO = mix(deep, foam, froth * 0.8);
		ROUGHNESS = mix(0.05, 0.4, froth);
		SPECULAR = 0.5;
		ALPHA = 1.0;
	} else {
		float v = UV.y - TIME * 2.2;
		float streak = smoothstep(0.35, 0.9, hash(vec2(floor(UV.x * 8.0), floor(v * 14.0))));
		ALBEDO = mix(vec3(0.62, 0.78, 0.82), foam, 0.45 + streak * 0.5);
		ROUGHNESS = 0.1;
		SPECULAR = 0.6;
		ALPHA = 0.78 + streak * 0.2;
	}
}
