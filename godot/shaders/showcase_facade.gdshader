shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

// Baked vertex alpha encodes masonry, trim, unlit glass, and lit glass.
uniform sampler2D plaster_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float night : hint_range(0.0, 1.0);
uniform float wetness : hint_range(0.0, 1.0);
varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec2 material_uv = vec2(dot(world_pos.xz, vec2(world_n.z, -world_n.x)), -world_pos.y);
	if (abs(world_n.y) > 0.5) {
		material_uv = world_pos.xz;
	}
	material_uv *= 0.31;
	vec2 dx = dFdx(material_uv);
	vec2 dy = dFdy(material_uv);
	float kind = COLOR.a;
	vec3 tint = COLOR.rgb;
	if (kind > 0.4) {
		vec3 n = normalize(NORMAL);
		vec3 reflected = (INV_VIEW_MATRIX * vec4(reflect(-normalize(VIEW), n), 0.0)).xyz;
		float sky = smoothstep(-0.34, 0.36, reflected.y);
		float angle = 1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
		float fresnel = angle * angle;
		vec3 horizon = mix(vec3(0.055, 0.063, 0.071), vec3(0.17, 0.24, 0.29), sky);
		ALBEDO = mix(tint * 0.63, horizon, (0.26 + fresnel * 0.46) * (1.0 - night * 0.63));
		ROUGHNESS = 0.24;
		METALLIC = 0.14;
		SPECULAR = 0.46;
		EMISSION = vec3(1.0, 0.65, 0.36) * night * step(0.7, kind) * (0.66 + tint.r * 2.6);
	} else {
		float grain = textureGrad(plaster_map, material_uv, dx, dy).r;
		ALBEDO = tint * mix(0.77, 1.12, grain) * (1.0 - wetness * 0.13);
		ROUGHNESS = mix(0.88, 0.65, wetness);
		ROUGHNESS = mix(ROUGHNESS, 0.49, step(0.16, kind));
		SPECULAR = 0.37;
	}
}
