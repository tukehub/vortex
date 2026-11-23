shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/vlore_lod.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform bool detail = false;
uniform float night = 0.0;
uniform float wetness = 0.0;
varying flat vec2 tile;
varying vec3 world_pos;
varying vec4 pigment;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tile = detail ? INSTANCE_CUSTOM.xy : vec2(round(COLOR.a * 3.0), 0.0);
	pigment = COLOR;
}

void fragment() {
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	// Opaque screen-door coverage works on Mobile. The matching shell always
	// fills uncovered pixels, including at the silhouette of a balcony.
	float coverage = detail ? smoothstep(96., 126., dist) : skyline_coverage(dist);
	if (screen_threshold(FRAGCOORD.xy) < coverage) {
		discard;
	}
	vec2 cell = fract(UV);
	float row = detail ? tile.y : (UV.y < 1.0 ? (mod(floor(UV.x), 3.0) == 0.0 ? 2.0 : 1.0) : 0.0);
	vec2 local = detail ? clamp(UV, vec2(0.), vec2(1.)) : cell;
	vec2 grid = vec2(4., 3.);
	vec2 coord = (vec2(tile.x, row) + mix(vec2(.005), vec2(.995), vec2(local.x, 1.-local.y))) / grid;
	vec2 dx = dFdx(UV) * vec2(1., -1.) / grid;
	vec2 dy = dFdy(UV) * vec2(1., -1.) / grid;
	vec3 tint = mix(vec3(.68), vec3(1.13), pigment.rgb);
	vec3 paint = textureGrad(atlas, coord, dx, dy).rgb;
	float glass = smoothstep(.018, .06, paint.b - paint.r);
	if (detail && pigment.a < .5) {
		paint = pigment.rgb;
		tint = vec3(1.);
		glass = 0.;
	}
	ALBEDO = paint * tint * (1.-.13*wetness);
	ROUGHNESS = mix(.86, .24, glass) - .08 * wetness;
	METALLIC = glass * .12;
	EMISSION = vec3(.82, .49, .23) * glass * night * .56;
}
