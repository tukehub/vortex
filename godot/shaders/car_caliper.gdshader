shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// All four brake calipers of a car in one mesh (car space). They do not spin
// with the wheels; the front pair (vertex COLOR.r = 1) turns with the
// steering about its wheel's upright, which `front_pivot` (x, z) locates.
uniform vec4 caliper_color : source_color = vec4(0.72, 0.1, 0.06, 1.0);
uniform float steer = 0.0;
uniform vec2 front_pivot = vec2(0.82, -1.245);

void vertex() {
	if (COLOR.r > 0.5) {
		vec2 pivot = vec2(sign(VERTEX.x) * front_pivot.x, front_pivot.y);
		vec2 d = VERTEX.xz - pivot;
		float c = cos(steer);
		float s = sin(steer);
		// Godot's rotation about +Y: x' = x c + z s, z' = -x s + z c.
		VERTEX.xz = pivot + vec2(d.x * c + d.y * s, -d.x * s + d.y * c);
		NORMAL.xz = vec2(NORMAL.x * c + NORMAL.z * s, -NORMAL.x * s + NORMAL.z * c);
	}
}

void fragment() {
	// Painted cast aluminium under a clear coat.
	ALBEDO = caliper_color.rgb;
	METALLIC = 0.1;
	ROUGHNESS = 0.42;
	CLEARCOAT = 0.6;
	CLEARCOAT_ROUGHNESS = 0.12;
}
