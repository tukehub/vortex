shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
#include "res://shaders/tree_dither.gdshaderinc"

uniform sampler2D bark_color : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D bark_normal : hint_normal, repeat_enable, filter_linear_mipmap;

void vertex() {
	tree_data = INSTANCE_CUSTOM;
}

void fragment() {
	if (tree_culled(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = texture(bark_color, UV).rgb * COLOR.rgb * mix(0.86, 1.13, tree_data.y);
	NORMAL_MAP = texture(bark_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.63;
	ROUGHNESS = 0.91;
	SPECULAR = 0.28;
}
