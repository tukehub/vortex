shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Pale limestone of the Uji i Ftohtë headland. Vertex colour carries the
// stone tint, stains and the maquis on its gentle slopes (sRGB); the rock
// photograph only lends its relief, projected on all three axes, as
// brightness and as a perturbed normal. Steep faces get faint vertical
// weathering streaks.

uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.12;
uniform float relief = 0.75;
uniform float wetness = 0.0;

varying vec3 w_pos;
varying vec3 w_nrm;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri_lum(vec3 p, vec3 b, float k) {
	vec3 lum_w = vec3(0.3, 0.59, 0.11);
	return dot(texture(rock_tex, p.zy * k).rgb, lum_w) * b.x + dot(texture(rock_tex, p.xz * k).rgb, lum_w) * b.y
		+ dot(texture(rock_tex, p.xy * k).rgb, lum_w) * b.z;
}

void fragment() {
	// Mostly faceted, like fractured limestone, a little of the smooth
	// normal so the facets do not flicker.
	vec3 flat_view = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(flat_view, -VERTEX) < 0.0) {
		flat_view = -flat_view;
	}
	vec3 flat_world = normalize((INV_VIEW_MATRIX * vec4(flat_view, 0.0)).xyz);
	vec3 n = normalize(mix(normalize(w_nrm), flat_world, 0.8));
	vec3 b = pow(abs(n), vec3(4.0));
	b /= b.x + b.y + b.z;
	vec2 ux = w_pos.zy * scale;
	vec2 uy = w_pos.xz * scale;
	vec2 uz = w_pos.xy * scale;
	// The photograph averages ~0.27 luminance; keep its contrast, not its
	// colour, at two scales (blocks and grain).
	float lum = tri_lum(w_pos, b, scale) * 0.6 + tri_lum(w_pos, b, scale * 3.7) * 0.4;
	float detail = clamp(lum / 0.27, 0.35, 1.8);
	// Whiteout-blended triplanar normal in world space.
	vec3 tx = texture(rock_nor, ux).xyz * 2.0 - 1.0;
	vec3 ty = texture(rock_nor, uy).xyz * 2.0 - 1.0;
	vec3 tz = texture(rock_nor, uz).xyz * 2.0 - 1.0;
	tx = vec3(tx.xy * relief + n.zy, abs(n.x));
	ty = vec3(ty.xy * relief + n.xz, abs(n.y));
	tz = vec3(tz.xy * relief + n.xy, abs(n.z));
	vec3 axis_sign = sign(n);
	tx.z *= axis_sign.x;
	ty.z *= axis_sign.y;
	tz.z *= axis_sign.z;
	vec3 nw = normalize(tx.zyx * b.x + ty.xzy * b.y + tz.xyz * b.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float steep = 1.0 - b.y;
	float streak = 0.9 + 0.1 * sin(w_pos.x * 1.9 + w_pos.z * 2.6 + 2.2 * sin(w_pos.y * 0.31));
	vec3 col = to_linear(COLOR.rgb) * mix(1.0, detail, 0.75) * mix(1.0, streak, steep);
	ALBEDO = col * (1.0 - 0.28 * wetness);
	ROUGHNESS = mix(0.92, 0.55, wetness);
	SPECULAR = 0.35;
}
