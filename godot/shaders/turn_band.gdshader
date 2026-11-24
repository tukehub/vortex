shader_type spatial;
render_mode unshaded, cull_disabled;
// Black chevrons on amber, repeating along the band. UV.x grows in the race
// direction, one chevron per unit, so every chevron points the way to go.

uniform sampler2D sign_face : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
	ALBEDO = texture(sign_face, UV).rgb;
}
