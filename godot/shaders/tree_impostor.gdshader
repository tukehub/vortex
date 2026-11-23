shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
#include "res://shaders/tree_dither.gdshaderinc"

uniform sampler2D impostors : source_color, repeat_disable, filter_linear_mipmap;

void vertex() {
	tree_data = INSTANCE_CUSTOM;
	vec3 to_camera = CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz;
	// A zero-scale slot has a finite direction and collapses off the raster.
	vec3 local_x = MODEL_MATRIX[0].xyz;
	vec3 local_z = MODEL_MATRIX[2].xyz;
	vec2 direction = vec2(dot(to_camera, local_x) / max(length(local_x), 0.00001),
		dot(to_camera, local_z) / max(length(local_z), 0.00001));
	direction = normalize(direction + vec2(0.00001));
	float frame = abs(direction.x) > abs(direction.y)
		? (direction.x >= 0.0 ? 1.0 : 3.0) : (direction.y >= 0.0 ? 0.0 : 2.0);
	VERTEX = vec3(direction.y * VERTEX.x, VERTEX.y, -direction.x * VERTEX.x);
	NORMAL = normalize(vec3(direction.x * 0.42, 0.83, direction.y * 0.42));
	UV = (vec2(frame * 128.0, tree_data.x * 160.0) + vec2(4.0) + UV * vec2(120.0, 152.0)) / 512.0;
}

void fragment() {
	if (tree_culled(FRAGCOORD.xy)) {
		discard;
	}
	vec4 baked = texture(impostors, UV);
	NORMAL = normalize(FRONT_FACING ? NORMAL : -NORMAL);
	ALBEDO = baked.rgb * tree_tint();
	ALPHA = baked.a;
	ALPHA_SCISSOR_THRESHOLD = 0.32;
	ROUGHNESS = 0.92;
	SPECULAR = 0.19;
	BACKLIGHT = ALBEDO * 0.23;
}
