shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform float water_y = -1.2;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D grain : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D grain_arm : hint_default_white, filter_linear_mipmap, repeat_enable;
instance uniform bool close_detail = true;

varying vec3 tp_pos;
varying vec3 tp_nrm;
varying vec4 variation;

#include "res://shaders/triplanar_detail.gdshaderinc"

void vertex() {
	tp_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tp_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	variation = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 weights = tp_weights(tp_nrm);
	vec3 p = tp_pos + variation.w * vec3(3.9, 7.1, 5.5);
	const float tile = .52;
	vec2 major = weights.y > max(weights.x, weights.z) ? p.xz : (weights.x > weights.z ? p.zy : p.xy);
	vec3 arm = texture(grain_arm, major * tile).rgb;
	vec3 sample_color = close_detail
		? tp_albedo(grain, p, weights, tile, vec3(1.0))
		: texture(grain, major * tile).rgb;
	float above = tp_pos.y - water_y;
	float splash = variation.y * (1.0 - smoothstep(.02, .22 + variation.y * 1.14, above));
	float wet = max(max(splash, 1.0 - smoothstep(-.25, .035, above)), .70 * wetness);
	if (close_detail) {
		vec3 n = tp_normal(grain_n, p, normalize(tp_nrm), weights, tile, mix(.75, .33, wet));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
	vec3 limestone = mix(vec3(.23, .205, .163), vec3(.41, .372, .302), variation.x);
	vec3 photo = clamp(sample_color / vec3(.236, .146, .082), .34, 1.74);
	float algae = variation.y * (1.0 - smoothstep(.04, .26, abs(above - .12)));
	float baked = clamp(COLOR.r, .36, 1.0);
	ALBEDO = limestone * mix(vec3(1.0), photo, .55) * mix(1.0,.49,wet)
		* mix(vec3(1.0), vec3(.72,.76,.53), algae*.58) * mix(.52,1.,baked);
	AO = arm.r * baked;
	AO_LIGHT_AFFECT = .30;
	ROUGHNESS = mix(clamp(arm.g * .84 + .12 + variation.z*.08, .61, .98), .26 + variation.z*.16, wet);
	SPECULAR = mix(.29, .54, wet);
}
