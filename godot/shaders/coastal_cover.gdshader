shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D sprays : source_color, repeat_disable, filter_linear_mipmap;
uniform bool middle = false;
uniform float wind_m = 0.03;
varying vec3 tint;

void vertex() {
	float metres = distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD);
	float handoff = smoothstep(21., 27., metres);
	float size = middle ? handoff * (1.-smoothstep(67., 80., metres)) : 1.-handoff;
	float height = max(0., VERTEX.y);
	if (wind_m > 0. && metres < 44.) {
		float phase = TIME * 1.6 + INSTANCE_CUSTOM.r * TAU;
		VERTEX.xz += vec2(.91,.41) * sin(phase) * wind_m * height * (1.-smoothstep(22.,44.,metres));
	}
	VERTEX *= size;
	tint = mix(vec3(.87,.93,.82),vec3(1.18,1.06,.88),INSTANCE_CUSTOM.g);
	tint *= mix(vec3(1.), vec3(.66,.86,.64), INSTANCE_CUSTOM.b);
}

void fragment() {
	NORMAL = normalize(FRONT_FACING ? NORMAL : -NORMAL);
	vec3 color = COLOR.rgb * tint;
	if (UV.x > .0001) {
		vec4 leaves = texture(sprays, UV);
		if (leaves.a < (middle ? .27 : .36)) {
			discard;
		}
		color *= leaves.rgb;
	}
	ALBEDO = color;
	ROUGHNESS = .94;
	SPECULAR = .16;
}
