shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

// Terrain splat: R road, G vegetation, B water, A urban (unused channels are grass/rock by slope).
uniform sampler2D splat : source_color, filter_linear, repeat_disable;
uniform float splat_span = 6000.0;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_urban : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_urban_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_road : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool coastal_ground = false;
uniform sampler2D ground_macro : filter_linear_mipmap, repeat_enable;
instance uniform bool detailed_hillside = false;
// Vlorë binds tex_rock and tex_rock_n to the shared 1K limestone.
uniform sampler2D tex_limestone_arm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray ground_layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_layers_pbr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool skanderbeg_square = false;
// Second, coarser texture scale that hides tiling in the distance.
uniform bool two_scale = true;
uniform float sea_level = -50.0;
// A real water surface (Sea) covers open water: the ground under it is seabed,
// and a sand beach rises out of it instead of painted water.
uniform bool sea_surface = false;
uniform float water_surface = -50.0;
// Signed shore distance on the near grid (tools/pipeline/water.py): below 0.5
// is land, its distance to the water 0..beach_span metres as 127/255..0.
uniform sampler2D shore_tex : filter_linear, repeat_disable;
uniform vec2 shore_origin = vec2(-4500.0);
uniform float shore_size = 9000.0;
uniform float beach_span = 60.0;
uniform vec3 sand_color : source_color = vec3(0.80, 0.72, 0.58);
// Beach detail (Poly Haven Coast Sand 04, 3.94 m tile): colour divided by its
// mean so sand_color keeps the tone; ARM green is roughness.
uniform sampler2D tex_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
const vec3 SAND_MEAN = vec3(0.117, 0.092, 0.053);
const float SAND_TILE = 3.94;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 water_color : source_color = vec3(0.02, 0.09, 0.14);
uniform vec3 grass_tint : source_color = vec3(0.78, 0.86, 0.62);
uniform vec3 urban_tint : source_color = vec3(0.72, 0.70, 0.66);

#include "res://shaders/square_paving.gdshaderinc"
#include "res://shaders/terrain_coastal.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;
varying float cam_dist;
varying vec2 relief;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cam_dist = length((VIEW_MATRIX * vec4(wpos, 1.0)).xyz);
	relief = detailed_hillside ? COLOR.rg : vec2(0.0);
}

// hash based detail noise to break tiling
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 suv = wpos.xz / splat_span + 0.5;
	vec4 sp = texture(splat, suv);
	float in_splat = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);
	sp *= in_splat;

	// Shared road and water masks remain registered to the baked map.
	vec2 uv_n = wpos.xz / 4.0;
	vec2 uv_f = wpos.xz / 41.0;
	float far_w = clamp((cam_dist - 120.0) / 500.0, 0.0, 1.0);
	vec3 up = normalize(wnrm);
	float slope = 1.0 - clamp(up.y, 0.0, 1.0);
	float above = wpos.y - water_surface;
	vec2 shore = vec2(beach_span, 0.0);
	if (sea_surface) {
		vec2 shore_uv = (wpos.xz - shore_origin) / shore_size;
		shore.y = step(0.0, shore_uv.x) * step(shore_uv.x, 1.0) * step(0.0, shore_uv.y) * step(shore_uv.y, 1.0);
		float code = texture(shore_tex, clamp(shore_uv, 0.0, 1.0)).r * 255.0;
		shore.x = clamp((127.0 - code) / 127.0, 0.0, 1.0) * beach_span;
	}

	float alt = clamp((wpos.y - 900.0) / 600.0, 0.0, 1.0);
	float rock_w = 0.0;
	vec3 base;
	vec3 urban = vec3(.25,.23,.20);
	vec3 nrm = vec3(.5,.5,1.0);
	vec3 n_urban = nrm;
	vec3 world_detail = vec3(0.);
	float rough;
	float ground_ao = 1.0;
	if (coastal_ground) {
		CoastGround ground = coastal_surface(wpos, up, cam_dist, sp, relief, shore, above, rock_w);
		base = ground.albedo;
		rough = ground.roughness;
		world_detail = ground.detail_normal;
		ground_ao = ground.ao;
	} else {
		// Each scale is fetched only where it has weight: inside 120 m the far
		// tiles, beyond 620 m the near tiles and their normals. The weights are 0
		// where the branches switch, so a quad straddling the seam cannot show
		// a wrong mip level. Phones skip three to six of the ~16 fetches a pixel.
		vec3 grass = vec3(0.0);
		vec3 rock = vec3(0.0);
		urban = vec3(0.0);
		vec3 n_grass = vec3(0.5, 0.5, 1.0);
		vec3 n_rock = n_grass;
		n_urban = n_grass;
		float near_w = two_scale ? 1.0 - far_w : 1.0;
		if (near_w > 0.0) {
			grass = texture(tex_grass, uv_n).rgb * near_w;
			rock = texture(tex_rock, uv_n).rgb * near_w;
			urban = texture(tex_urban, uv_n).rgb * near_w;
			n_grass = mix(texture(tex_grass_n, uv_n).rgb, n_grass, far_w);
			n_rock = mix(texture(tex_rock_n, uv_n).rgb, n_rock, far_w);
			n_urban = mix(texture(tex_urban_n, uv_n).rgb, n_urban, far_w);
		}
		if (near_w < 1.0) {
			grass += texture(tex_grass, uv_f).rgb * far_w;
			rock += texture(tex_rock, uv_f).rgb * far_w;
			urban += texture(tex_urban, uv_f).rgb * far_w;
		}
		grass *= grass_tint;
		urban *= urban_tint;
		rock_w = smoothstep(0.35, 0.65, slope + (vnoise(wpos.xz * 0.02) - 0.5) * 0.3);
		rock_w = max(rock_w, alt * 0.8);
		base = mix(grass, rock, rock_w);
		nrm = mix(n_grass, n_rock, rock_w);
		rough = mix(0.92, 0.85, rock_w);
	}

	float urban_w = sp.a * (1.0 - rock_w * 0.5);
	if (coastal_ground) {
		// The OSM residential polygon spans whole hillsides. Streets and
		// footprints are drawn separately, and open slopes show through it.
		float hillside = smoothstep(12., 38., wpos.y) * (.84 + .16 * smoothstep(.005, .07, slope));
		float streets = smoothstep(.035, .33, sp.r);
		urban_w *= (1.0 - max(hillside * .93, sp.g * .85)) * mix(.24, .83, streets);
		float grit = .58 * (1.0 - smoothstep(28.,130.,cam_dist));
		if (urban_w > .015 && grit > .005) {
			urban = mix(urban, texture(tex_urban, uv_n).rgb * urban_tint, grit);
		}
	}
	base = mix(base, urban, urban_w);
	nrm = mix(nrm, n_urban, urban_w);
	rough = mix(rough, 0.8, urban_w);

	float road_w = smoothstep(0.25, 0.7, sp.r);
	if (road_w > .001) {
		vec3 road = texture(tex_road, uv_n * 0.5).rgb * 0.85;
		base = mix(base, road, road_w);
	}
	nrm = mix(nrm, vec3(0.5, 0.5, 1.0), road_w);
	rough = mix(rough, 0.75, road_w);
	float hardscape = 1.0 - (1.0 - urban_w) * (1.0 - road_w);
	world_detail *= 1.0 - hardscape;
	ground_ao = mix(ground_ao, 1.0, hardscape);
	if (!coastal_ground) {
		base = mix(base, base * vec3(0.72, 0.9, 0.6), sp.g * 0.6 * (1.0 - road_w));
	}

	// A geographically placed, softly edged paving area around the monument.
	// The road is separate geometry above the terrain, so this cannot cover it.
	if (skanderbeg_square) {
		vec2 square = abs(wpos.xz - vec2(20.0, -55.0));
		float square_w = (1.0 - smoothstep(76.0, 84.0, square.x))
			* (1.0 - smoothstep(75.0, 83.0, square.y));
		// The square's own slabs: rows of mixed stone, polished.
		float paving_rough;
		float paving_joint;
		vec3 paving = square_paving(wpos.xz, paving_rough, paving_joint);
		base = mix(base, paving, square_w);
		nrm = mix(nrm, vec3(0.5, 0.5, 1.0), square_w);
		rough = mix(rough, paving_rough, square_w);
	}

	// water
	float water_w = max(smoothstep(0.3, 0.8, sp.b), 1.0 - smoothstep(-1.5, 0.5, wpos.y - sea_level));
	if (sea_surface) {
		// Seabed under the surface; a sand beach along the shore, wet at the
		// waterline, never over roads or up a cliff.
		float beach = (1.0 - smoothstep(16.0, 34.0, shore.x)) * shore.y;
		float sand_w = beach * (1.0 - road_w) * (1.0 - smoothstep(3.0, 6.0, above)) * smoothstep(0.75, 0.9, wnrm.y);
		float wet_sand = 1.0 - smoothstep(0.0, 0.6, above);
		// The beach is a thin band: fetch its three maps only on it (sand_w
		// eases in from 0, so the branch edge never shows).
		if (!coastal_ground && sand_w > 0.0) {
			vec2 sand_uv = wpos.xz / SAND_TILE;
			vec3 grain = texture(tex_sand, sand_uv).rgb / SAND_MEAN;
			// The grain fades with distance like the other near textures.
			grain = mix(grain, vec3(1.0), far_w);
			vec3 sand_arm = texture(tex_sand_arm, sand_uv).rgb;
			base = mix(base, sand_color * grain * sand_arm.r * (1.0 - 0.35 * wet_sand), sand_w);
			rough = mix(rough, mix(sand_arm.g, 0.45, wet_sand), sand_w);
			vec3 sand_n = mix(texture(tex_sand_n, sand_uv).rgb, vec3(0.5, 0.5, 1.0), far_w);
			nrm = mix(nrm, mix(sand_n, vec3(0.5, 0.5, 1.0), wet_sand * 0.6), sand_w);
		}
		// Mapped rivers and ponds keep their painted water above the sea.
		water_w = smoothstep(0.3, 0.8, sp.b) * step(0.3, above);
		base = mix(base, sand_color * 0.4, 1.0 - step(0.0, above));
	}
	base = mix(base, water_color, water_w);
	rough = mix(rough, 0.05, water_w);
	nrm = mix(nrm, vec3(0.5, 0.5, 1.0), water_w);
	world_detail *= (1.0-water_w)*smoothstep(-.5,.25,above);
	float metal = 0.0;

	// snow cover
	float snow_w = snow * smoothstep(0.3, 0.8, wnrm.y) * (1.0 - water_w) * (1.0 - road_w * 0.7);
	snow_w = max(snow_w, alt * (1.0 - water_w) * 0.9);
	base = mix(base, vec3(0.92, 0.94, 0.98), snow_w);
	rough = mix(rough, 0.6, snow_w);

	// wet surfaces darken and sharpen
	float wet_w = wetness * (1.0 - snow_w) * (1.0 - water_w);
	base *= 1.0 - 0.45 * wet_w;
	rough = mix(rough, 0.18, wet_w * (0.6 + 0.4 * road_w));

	if (!coastal_ground) {
		base *= vnoise(wpos.xz * 0.12) * 0.16 + 0.92;
	} else {
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(up + world_detail * (1.0 - snow_w) * (1.0 - wet_w*.38)), 0.0)).xyz);
	}
	AO = mix(ground_ao, 1.0, max(water_w, snow_w));

	ALBEDO = base;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = mix(0.5, 0.7, water_w);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = coastal_ground ? 0.0 : 0.6;
	// faint urban glow at night for distant city blocks
	EMISSION = vec3(1.0, 0.72, 0.4) * urban_w * night * 0.012 * far_w;
}
