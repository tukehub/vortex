shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Procedural street furniture (StreetProps): the vertex colours give paint
// and tone; ambientCG Metal032 adds brushed-steel grain and relief, projected
// in world space (the meshes have no UVs). Off on low quality.
uniform sampler2D metal : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D metal_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D metal_arm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool detail = true;
uniform float roughness = 0.7;
const vec3 METAL_MEAN = vec3(0.208, 0.253, 0.300);
const float METAL_SCALE = 1.0;

varying vec3 tp_pos;
varying vec3 tp_nrm;

#include "res://shaders/triplanar_detail.gdshaderinc"

void vertex() {
	tp_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tp_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float rough = roughness;
	if (detail) {
		vec3 n0 = normalize(tp_nrm) * (FRONT_FACING ? 1.0 : -1.0);
		vec3 w = tp_weights(n0);
		// Grain only, not the photo's blue cast: its luminance around 1.
		vec3 g = tp_albedo(metal, tp_pos, w, METAL_SCALE, METAL_MEAN);
		col *= mix(1.0, dot(g, vec3(0.2126, 0.7152, 0.0722)), 0.6);
		rough = clamp(roughness * (0.6 + 0.8 * tp_rough(metal_arm, tp_pos, w, METAL_SCALE)), 0.2, 1.0);
		vec3 n = tp_normal(metal_n, tp_pos, n0, w, METAL_SCALE, 0.6);
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
