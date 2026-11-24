shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;
// Lungomare ground: pale stone paving in square slabs, and lawns cut by a
// diamond grid of diagonal paved paths (after aerial photographs).
// UV.x = metres along the seafront, UV.y = metres across it from the road
// centreline. COLOR.r = 0 paving, 1 lawn.

uniform vec3 stone : source_color = vec3(0.78, 0.76, 0.71);
uniform vec3 joint : source_color = vec3(0.66, 0.64, 0.60);
uniform vec3 grass : source_color = vec3(0.34, 0.47, 0.24);
uniform sampler2D turf : source_color, filter_linear_mipmap, repeat_enable;
// Precast stone paving (Poly Haven, 2.24 m tile); colour divided by its mean
// so `stone` keeps the tone. ARM green is roughness.
uniform sampler2D paving_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paving_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paving_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
const vec3 PAVING_MEAN = vec3(0.178, 0.136, 0.083);
const float PAVING_TILE = 2.24;
uniform float slab = 1.2;
uniform float path_pitch = 34.0;
uniform float path_half = 1.1;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV;
	vec2 puv = p / PAVING_TILE;
	vec3 arm = texture(paving_arm, puv).rgb;
	vec3 paving = stone * (texture(paving_tex, puv).rgb / PAVING_MEAN) * arm.r;
	// Lawn with diagonal paths both ways.
	float a = abs(mod(p.x + p.y, path_pitch) - path_pitch * 0.5);
	float b = abs(mod(p.x - p.y, path_pitch) - path_pitch * 0.5);
	// Distance to the nearest path centreline of either family.
	float d = path_pitch * 0.5 - max(a, b);
	float path = 1.0 - smoothstep(path_half - 0.15, path_half + 0.15, d);
	vec3 blades = texture(turf, p * .31).rgb;
	vec3 lawn = grass * (.56 + 1.7 * blades) * (.92 + .08 * sin(p.y * .34 + sin(p.x * .12)));
	float is_lawn = COLOR.r * (1.0 - path);
	ALBEDO = mix(paving, lawn, is_lawn) * (1.0 - 0.3 * wetness * (1.0 - is_lawn));
	ROUGHNESS = mix(mix(arm.g, 0.25, wetness), 0.95, is_lawn);
	NORMAL_MAP = mix(texture(paving_n, puv).rgb, vec3(0.5, 0.5, 1.0), is_lawn);
	SPECULAR = 0.4;
}
