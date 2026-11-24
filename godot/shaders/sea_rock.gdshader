shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Limestone armour stones at the waterline (SeaRocks): ochre and brown by
// vertex colour; darker, glossier and a little green where the waves keep
// them wet, up to `splash` metres above the water. Rain wets them all over.
uniform float water_y = 0.0;
uniform float splash = 0.9;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
// Limestone grain (Poly Haven Rock Face 03, 2.7 m tile), triplanar in world
// space; the vertex colours keep the tone.
uniform sampler2D grain : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grain_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D grain_arm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool detail = true;
const vec3 GRAIN_MEAN = vec3(0.236, 0.146, 0.082);
const float GRAIN_SCALE = 1.0 / 2.7;

varying float wy;
varying vec3 tp_pos;
varying vec3 tp_nrm;

#include "res://shaders/triplanar_detail.gdshaderinc"

void vertex() {
	tp_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tp_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wy = tp_pos.y;
}

void fragment() {
	float above = wy - water_y;
	float wet = 1.0 - smoothstep(0.05, splash, above);
	wet = max(wet, wetness * 0.8);
	// Vertex colours are sRGB; shading is linear.
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	// Algae just above the water, darker wet stone, dry crust above.
	col = mix(col, col * vec3(0.55, 0.6, 0.42), (1.0 - smoothstep(0.0, 0.25, above)) * step(-0.4, above) * 0.7);
	col *= mix(1.0, 0.5, wet);
	float rough = 0.82;
	if (detail) {
		vec3 w = tp_weights(tp_nrm);
		col *= mix(tp_albedo(grain, tp_pos, w, GRAIN_SCALE, GRAIN_MEAN), vec3(1.0), 0.25);
		rough = tp_rough(grain_arm, tp_pos, w, GRAIN_SCALE);
		vec3 n = tp_normal(grain_n, tp_pos, normalize(tp_nrm), w, GRAIN_SCALE, mix(1.0, 0.5, wet));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.28, wet);
	SPECULAR = mix(0.4, 0.6, wet);
}
