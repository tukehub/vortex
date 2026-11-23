shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
#include "res://shaders/tree_dither.gdshaderinc"

uniform sampler2D sprays : source_color, repeat_disable, filter_linear_mipmap;
uniform float wind_m = 0.0;

void vertex() {
	tree_data = INSTANCE_CUSTOM;
	// The branch mesh stays still. Fine stems in each spray travel with its leaves.
	if (wind_m > 0.0) {
		float distance_to_eye = distance(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
		float strength = wind_m * (1.0 - smoothstep(35.0, 112.0, distance_to_eye));
		float phase = TIME * 1.55 + tree_data.y * TAU + VERTEX.y * 0.48;
		VERTEX.xz += vec2(0.92, 0.41) * (sin(phase) * strength);
	}
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
