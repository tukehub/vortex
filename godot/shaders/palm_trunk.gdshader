shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Date palm trunks (Palms): vertex colours give the tone, Poly Haven Palm
// Tree Bark (1.3 m tile) the leaf-base scales, projected in object space so
// the rings stay horizontal on every instance.
uniform sampler2D bark : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_arm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool detail = true;
const vec3 BARK_MEAN = vec3(0.354, 0.299, 0.240);
const float BARK_SCALE = 1.0 / 1.3;

varying vec3 tp_pos;
varying vec3 tp_nrm;

#include "res://shaders/triplanar_detail.gdshaderinc"

void vertex() {
	tp_pos = VERTEX;
	tp_nrm = NORMAL;
}

void fragment() {
	// Vertex colours are sRGB; shading is linear.
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	float rough = 0.9;
	if (detail) {
		vec3 n0 = normalize(tp_nrm);
		vec3 w = tp_weights(n0);
		col *= tp_albedo(bark, tp_pos, w, BARK_SCALE, BARK_MEAN);
		rough = tp_rough(bark_arm, tp_pos, w, BARK_SCALE);
		vec3 n = tp_normal(bark_n, tp_pos, n0, w, BARK_SCALE, 1.0);
		NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(n, 0.0))).xyz);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
