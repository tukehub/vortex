shader_type spatial;
#include "res://shaders/vlore_lod.gdshaderinc"

uniform sampler2D tiles : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.)).xyz;
}

void fragment() {
	float metres = distance(world_pos, CAMERA_POSITION_WORLD);
	if (screen_threshold(FRAGCOORD.xy) < skyline_coverage(metres)) {
		discard;
	}
	ALBEDO = COLOR.rgb * texture(tiles, world_pos.xz * .12).rgb;
	ROUGHNESS = .85;
}
