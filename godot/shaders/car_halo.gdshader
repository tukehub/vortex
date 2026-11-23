shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// The bloom an eye sees around a lit lamp: a small hot core and a soft
// spread, on a camera-facing quad. It shows only while the lamp points
// toward the camera (`lamp_dir`, in the car's space), so a car seen from the
// side or behind has no headlight halo.
uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform vec3 lamp_dir = vec3(0.0, 0.0, -1.0);

void vertex() {
	// Billboard that keeps the node's scale.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	float glow = exp(-r2 * 22.0) + 0.28 * exp(-r2 * 5.0);
	glow *= 1.0 - smoothstep(0.7, 1.0, r2);
	vec3 dir = normalize((MODEL_MATRIX * vec4(lamp_dir, 0.0)).xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - NODE_POSITION_WORLD);
	float facing = smoothstep(0.05, 0.65, dot(dir, to_cam));
	ALBEDO = tint.rgb * energy * glow * facing;
}
