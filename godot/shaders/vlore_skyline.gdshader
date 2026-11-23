shader_type spatial;
render_mode cull_back, depth_draw_opaque;
#include "res://shaders/vlore_lod.gdshaderinc"

uniform float night;
uniform float wetness;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.)).xyz;
}

void fragment() {
	vec3 face = cross(dFdx(VERTEX), dFdy(VERTEX));
	float metres = distance(world_pos, CAMERA_POSITION_WORLD);
	float threshold = screen_threshold(FRAGCOORD.xy);
	if (threshold >= skyline_coverage(metres) || threshold < smoothstep(1880., 2040., metres)) {
		discard;
	}
	NORMAL = normalize(dot(face, VIEW) < 0. ? -face : face);
	ALBEDO = COLOR.rgb * (1.-.13*wetness);
	ROUGHNESS = .8;
	EMISSION = vec3(.82,.49,.23) * night * COLOR.a * .56;
}
