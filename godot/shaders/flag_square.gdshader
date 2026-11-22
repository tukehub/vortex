shader_type spatial;

// Cut limestone around the monument. The raised island shares the 15 m
// footprint of the obstacle in the points simulation.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_tex : filter_linear_mipmap, repeat_enable;
uniform float island_radius = 15.0;
varying vec2 metres;

void vertex() {
	metres = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 cell = metres / vec2(1.2, 0.65);
	cell.x += 0.5 * mod(floor(cell.y), 2.0);
	vec2 edge = min(fract(cell), 1.0 - fract(cell)) * vec2(1.2, 0.65);
	float distance_to_joint = min(edge.x, edge.y);
	float pixel = max(length(fwidth(metres)), 0.002);
	float joint = 0.014 / (pixel + 0.014) * (1.0 - smoothstep(0.003, 0.012 + pixel, distance_to_joint));
	float radius = length(metres) - island_radius;
	float border = 1.0 - smoothstep(0.11, 0.11 + pixel, min(abs(radius - 2.2), abs(radius - 3.0)));
	vec2 uv = metres * 0.135;
	vec3 mineral = texture(albedo_tex, uv).rgb;
	float tone = fract(sin(dot(floor(cell), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 limestone = mix(vec3(0.23, 0.20, 0.16), vec3(0.43, 0.39, 0.32), mineral.r);
	ALBEDO = limestone * mix(0.94, 1.04, tone) * mix(1.0, 0.52, joint) * mix(1.0, 0.40, border);
	AO = mix(0.60, 1.0, smoothstep(0.0, 1.15, radius));
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 0.4;
	ROUGHNESS = clamp(0.52 + 0.32 * texture(roughness_tex, uv).r + 0.13 * joint, 0.4, 1.0);
}
