shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
#include "res://shaders/tree_dither.gdshaderinc"

uniform sampler2D sprays : source_color, repeat_disable, filter_linear_mipmap;

void vertex() {
	tree_data = INSTANCE_CUSTOM;
}

void fragment() {
	if (tree_culled(FRAGCOORD.xy)) {
		discard;
	}
	vec4 spray = texture(sprays, UV);
	// Rounded, authored crown normals must point out of the crown from either
	// side of each card. Godot flips the interpolated normal on a back face.
	NORMAL = normalize(FRONT_FACING ? NORMAL : -NORMAL);
	ALBEDO = spray.rgb * COLOR.rgb * tree_tint();
	ALPHA = spray.a;
	// Preserve small leaves as projected texels shrink at the far end of LOD1.
	ALPHA_SCISSOR_THRESHOLD = mix(0.42, 0.30, smoothstep(20.0, 130.0, -VERTEX.z));
	ROUGHNESS = 0.84;
	SPECULAR = 0.24;
	BACKLIGHT = ALBEDO * vec3(0.32, 0.44, 0.23);
}
