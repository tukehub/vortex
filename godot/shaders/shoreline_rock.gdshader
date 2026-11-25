shader_type spatial;
// Breakwater boulders: the cliff's limestone photo projected in world space
// (triplanar, no UV stretching), wet below the water line: albedo x0.45 and
// a glossy 0.2 roughness up to the splash height, blending over 0.5 m.
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile = 0.35;          // repeats per metre
uniform float water_y = -1.2;       // world height of the sea surface
uniform float splash = 0.6;         // wet this far above it
uniform float wet_darken = 0.45;
uniform float wet_rough = 0.2;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec2 ux = wpos.zy * tile, uy = wpos.xz * tile, uz = wpos.xy * tile;
	vec3 albedo = texture(albedo_tex, ux).rgb * w.x + texture(albedo_tex, uy).rgb * w.y + texture(albedo_tex, uz).rgb * w.z;
	float rough = texture(rough_tex, ux).r * w.x + texture(rough_tex, uy).r * w.y + texture(rough_tex, uz).r * w.z;
	// One normal sample on the dominant plane keeps phones at four fetches.
	vec2 major = w.y > max(w.x, w.z) ? uy : (w.x > w.z ? ux : uz);
	NORMAL_MAP = texture(normal_tex, major).rgb;
	float wet = 1.0 - smoothstep(water_y + splash - 0.25, water_y + splash + 0.25, wpos.y);
	ALBEDO = albedo * COLOR.rgb * mix(1.0, wet_darken, wet);
	ROUGHNESS = mix(rough, wet_rough, wet);
	SPECULAR = mix(0.5, 0.65, wet);
}
