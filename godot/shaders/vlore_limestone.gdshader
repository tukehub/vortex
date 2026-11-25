shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D stone_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D scrub_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D landscape : filter_linear_mipmap, repeat_enable;
uniform float water_y = -1.2;
varying vec3 world;
varying vec3 normal_world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 direction = normalize(normal_world);
	vec3 axis = pow(abs(direction), vec3(4.0));
	axis /= dot(axis, vec3(1.0));
	vec2 x_uv = vec2(world.z, world.y) * vec2(.22, .156);
	vec2 y_uv = world.xz * .22;
	vec2 z_uv = world.xy * vec2(.22, .156);
	vec3 stone = texture(stone_map, x_uv).rgb * axis.x
		+ texture(stone_map, y_uv).rgb * axis.y + texture(stone_map, z_uv).rgb * axis.z;
	vec2 major = axis.y > max(axis.x, axis.z) ? y_uv : (axis.x > axis.z ? x_uv : z_uv);
	vec3 arm = texture(rock_arm, major).rgb;
	// Bedding dips into the headland. The vertex fracture field interrupts
	// bands at joints while the photo carries fine pits and surface grain.
	float beds = world.y * .76 + world.x * .056 - world.z * .071;
	beds += .34 * sin(world.z * .19 + .27 * sin(world.x * .18));
	float lamina = smoothstep(.025, .20, abs(fract(beds + .5) - .5));
	float seams = (1.0 - lamina) * (.27 + COLOR.b * .25);
	vec3 limestone = vec3(.40,.379,.334) * mix(vec3(1.0), clamp(stone * vec3(3.4,4.2,5.1), .28, 1.65), .66);
	limestone *= mix(vec3(1.0), vec3(.61,.54,.45), seams);
	vec3 land = texture(landscape, world.xz / 1580.0).rgb;
	float grain = dot(texture(scrub_map, world.xz / 4.7).rgb, vec3(.22,.65,.13));
	vec3 soil = mix(vec3(.19,.126,.072), vec3(.087,.14,.058), smoothstep(.20,.66,land.r));
	soil *= .48 + grain * 4.1;
	float exposed = clamp(COLOR.g * mix(.81, 1.12, 1.0 - direction.y), 0., 1.);
	float splash = (1. - smoothstep(water_y + .12, water_y + 1.7, world.y)) * exposed;
	ALBEDO = mix(soil, limestone, exposed) * mix(.58, 1., COLOR.r) * mix(1., .64, splash);
	AO = mix(COLOR.r, COLOR.r * arm.r, exposed * .45);
	AO_LIGHT_AFFECT = .34;
	ROUGHNESS = mix(.91, mix(.78, arm.g, .62), exposed) - splash * .25;
	SPECULAR = .31 + splash * .15;
}
