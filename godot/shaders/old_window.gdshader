shader_type spatial;
// Windows of the old quarters (old_quarter.gd): one quad per window from the
// Berat window atlas (tools/build_berat_windows.py). Alpha marks the glass:
// glossy by day, and at night a warm light behind some of them. COLOR.r is
// the window's own brightness, COLOR.g whether anyone is home.
render_mode cull_back;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float night : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * mix(1.0, 0.55, t.a * night);
	ROUGHNESS = mix(0.8, 0.1, t.a);
	SPECULAR = mix(0.3, 0.65, t.a);
	float home = step(0.5, COLOR.g);
	EMISSION = vec3(1.0, 0.7, 0.4) * t.a * night * home * (0.7 + COLOR.r * 0.9) * 1.8;
}
