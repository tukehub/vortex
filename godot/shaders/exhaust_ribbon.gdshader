shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

void fragment() {
	float edge = 1.0 - smoothstep(0.0, 0.5, abs(UV.x - 0.5));
	ALBEDO = COLOR.rgb;
	ALPHA = edge * COLOR.a;
}
