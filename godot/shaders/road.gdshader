shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

// UV: x = metres across the centreline (negative left), y = metres along the lap.
uniform sampler2D tex_asphalt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_asphalt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_asphalt_r : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float half_w = 10.0;
uniform float track_len = 5000.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 asphalt_tint : source_color = vec3(0.90, 0.92, 0.96);
uniform vec3 line_white : source_color = vec3(0.9, 0.9, 0.86);
uniform vec3 line_yellow : source_color = vec3(0.95, 0.75, 0.2);
uniform float lane_count = 4.0;
// A one-way carriageway has a dashed white lane line down its middle
// instead of the yellow centre line of a two-way road.
uniform bool one_way = false;
uniform float start_s = 0.0;
uniform vec2 stone_section = vec2(0.0); // start and length in metres
// Road marks (plan 3.5): zebra crossings as (s, width) along the lap, from
// props.json "road_marks" (OSM highway=crossing nodes, or one before each
// signalised junction where none is mapped), and procedural manholes, kerb
// gullies and repaired patches placed by hashing the lap into cells.
const int MAX_CROSSINGS = 24;
uniform vec2 crossings[24];
uniform int crossing_count = 0;
// R8, one texel per CROSSING_CELL metres of lap: crossing index + 1, or 0.
uniform sampler2D crossing_map : filter_nearest, repeat_disable;
const float CROSSING_CELL = 8.0;
uniform float detail = 1.0; // 0 skips manholes, gullies and patches (low quality)

uniform float showcase_length = 0.0;
uniform float showcase_direction = 1.0;

varying vec2 ruv;
varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
// Sin-free cell hash for the road hardware: float32-exact on every GPU, so
// RoadMesh.hardware_near() can tell where covers and patches are.
float cell_hash(float c, float salt) {
	vec3 p3 = fract(vec3(c, salt, c) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
// A line of half width `hw` at distance `d`, edge filtered over `aa` metres.
// Thinner than a pixel it fades with its coverage instead of aliasing.
float line_mask(float d, float hw, float aa) {
	float w = max(hw, aa * 0.5);
	return (1.0 - smoothstep(w - aa * 0.5, w + aa * 0.5, d)) * min(1.0, hw / w);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	ruv = UV;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = ruv.x;
	float along = ruv.y;
	float city_s = mod(along * showcase_direction, track_len);
	float showcase = smoothstep(0.0, 8.0, min(city_s, showcase_length - city_s));
	vec2 tuv = vec2(across, along) / 5.0;
	// second asphalt sample rotated to kill repetition
	vec2 tuv2 = vec2(along, -across) / 7.3;
	vec3 asphalt = mix(texture(tex_asphalt, tuv).rgb, texture(tex_asphalt, tuv2).rgb, 0.5) * asphalt_tint;
	vec3 n1 = texture(tex_asphalt_n, tuv).rgb;
	vec3 n2 = texture(tex_asphalt_n, tuv2).rgb;
	// The second sample's UVs are rotated 90 degrees; rotate its tangent-space
	// direction back before blending or the surface grain lights incorrectly.
	vec3 nrm = mix(n1, vec3(1.0 - n2.g, n2.r, n2.b), 0.5);
	float aggregate = texture(tex_asphalt_r, tuv).g;  // asphalt_02 ARM: G = roughness
	float rough = aggregate * 0.45 + 0.5;
	// A darker, matte gutter ties the asphalt to the physical curb. The outer
	// edge blends toward the shoulder instead of reading as a bright raised slab.
	float gutter = smoothstep(half_w - 1.0, half_w + 0.3, abs(across));
	asphalt *= 1.0 - gutter * 0.10;
	asphalt = mix(asphalt, asphalt * vec3(0.78, 0.74, 0.65), (1.0 - COLOR.a) * 0.6);
	rough = min(0.98, rough + gutter * 0.08);

	// darker tyre tracks in the lanes
	float lane_w = 2.0 * half_w / lane_count;
	float lane_pos = fract((across + half_w) / lane_w);
	float wear = exp(-pow((lane_pos - 0.3) * 6.0, 2.0)) + exp(-pow((lane_pos - 0.7) * 6.0, 2.0));
	asphalt *= 1.0 - 0.09 * wear;

	// Patch seams use broad, staggered cells. Mipmapped asphalt roughness
	// breaks up the edge without introducing a second detail map.
	if (showcase > 0.0 && detail > 0.5) {
		vec2 patch_uv = vec2(wpos.x / 4.7, wpos.z / 8.3);
		patch_uv.x += mod(floor(patch_uv.y), 2.0) * 0.5;
		vec2 joints = abs(fract(patch_uv) - 0.5);
		vec2 widths = vec2(0.42, 0.41) + (aggregate - 0.5) * 0.085;
		float seam = max(joints.x - widths.x, joints.y - widths.y);
		float patch_aa = max(0.018, max(fwidth(patch_uv.x), fwidth(patch_uv.y)));
		float repaired = (1.0 - smoothstep(-patch_aa, patch_aa, seam))
			* step(0.76, hash(floor(patch_uv))) * showcase;
		asphalt *= 1.0 - repaired * (0.12 + aggregate * 0.15);
		rough = mix(rough, 0.63, repaired * 0.7);
	}

	asphalt *= 1.0 - showcase * (0.17 + 0.10 * gutter + 0.042 * wear);

	// lane markings: dashed white between lanes, solid yellow centre, solid white edges.
	// Edges are filtered over the pixel's footprint (fwidth): sharp up close,
	// and far away a thin line fades to its coverage instead of breaking into
	// crawling stair-steps (MSAA cannot fix aliasing inside a shader).
	float aa_x = max(fwidth(across), 0.002);
	float aa_s = max(fwidth(along), 0.002);
	float edge = line_mask(abs(abs(across) - (half_w - 0.35)), 0.2, aa_x);
	float centre = line_mask(abs(across), 0.17, aa_x);
	float centre_dash = 0.0;
	if (one_way) {
		centre_dash = line_mask(abs(across), 0.12, aa_x);
		centre = 0.0;
	}
	// 3 m dashes, 3 m gaps, with filtered ends.
	float dash_pos = fract(along / 6.0) * 6.0;
	float dash = smoothstep(3.0 - aa_s, 3.0 + aa_s, dash_pos) * (1.0 - smoothstep(6.0 - aa_s, 6.0, dash_pos));
	float lane_line = 0.0;
	for (int i = 1; i < 4; i++) {
		if (float(i) >= lane_count) break; // dividers only, never on an edge
		float lx = -half_w + float(i) * lane_w;
		if (abs(float(i) * 2.0 - lane_count) < 0.5) continue; // centre handled separately
		lane_line = max(lane_line, line_mask(abs(across - lx), 0.14, aa_x) * dash);
	}
	lane_line = max(lane_line, centre_dash * dash);
	// Street hardware set into the asphalt.
	float grate = 0.0;
	if (detail > 0.5) {
		// Repaired patches: darker, finer asphalt in a sealed rectangle.
		float pc = floor(along / 31.0);
		if (showcase <= 0.0 && cell_hash(pc, 4.7) < 0.38) {
			float plen = 1.6 + cell_hash(pc, 1.3) * 4.5;
			float pwid = 1.0 + cell_hash(pc, 2.9) * 2.4;
			float ps = (pc + 0.15 + 0.7 * cell_hash(pc, 8.1)) * 31.0;
			float pa = (cell_hash(pc, 5.5) * 2.0 - 1.0) * max(0.0, half_w - pwid * 0.5 - 0.8);
			vec2 q = abs(vec2(across - pa, along - ps)) - vec2(pwid, plen) * 0.5;
			float sdist = max(q.x, q.y);
			if (sdist < 0.0) {
				// Fresh patches are black and close-grained; age greys them
				// toward the road around them.
				float age = cell_hash(pc, 9.9);
				// Relative to the road it sits in (the texture is sRGB, so the
				// surrounding asphalt is only ~0.1 in linear light).
				float grey = dot(asphalt, vec3(0.333));
				vec3 fresh = vec3(grey * 0.42) * (0.92 + 0.16 * vnoise(vec2(across, along) * 3.0));
				asphalt = mix(fresh, asphalt * 0.92, 0.08 + 0.7 * age);
				// Matte: the sky must not sheen off it at a grazing angle.
				nrm = mix(nrm, vec3(0.5, 0.5, 1.0), 0.25 * (1.0 - age));
				rough = mix(0.96, rough, age);
				// Bitumen seal along the cut, a little ragged.
				float seam = 1.0 - smoothstep(0.02, 0.07 + 0.03 * vnoise(vec2(across, along) * 9.0), -sdist);
				asphalt = mix(asphalt, vec3(0.025), seam * 0.8);
			}
		}
		// Round cast-iron manhole covers in the middle of a lane.
		float mc = floor(along / 22.0);
		if (cell_hash(mc, 6.1) < 0.5) {
			float lane_i = floor(cell_hash(mc, 3.7) * lane_count);
			vec2 o = vec2(across - (-half_w + lane_w * (lane_i + 0.5)), along - (mc + 0.2 + 0.6 * cell_hash(mc, 2.2)) * 22.0);
			float r = length(o);
			if (r < 0.42) {
				float body = 1.0 - smoothstep(0.315, 0.33, r);
				float frame = (1.0 - smoothstep(0.385, 0.40, r)) * (1.0 - body);
				float ring = step(0.5, fract(r * 13.0)) * step(0.07, r);
				float rib = step(0.82, fract(atan(o.y, o.x) * 12.0 / 6.28318));
				float raised = max(ring, rib) * body;
				// Dark, slightly rusty cast iron; tyres polish the raised pattern.
				vec3 iron = vec3(0.05, 0.045, 0.04) * (0.8 + 0.4 * vnoise(o * 28.0));
				asphalt = mix(asphalt, mix(iron, iron * 1.5 + 0.015, raised), body);
				asphalt = mix(asphalt, vec3(0.055, 0.052, 0.048), frame);
				asphalt *= 1.0 - 0.75 * (1.0 - smoothstep(0.0, 0.012, abs(r - 0.338)));
				rough = mix(rough, mix(0.7, 0.42, raised), body);
				rough = mix(rough, 0.62, frame);
				nrm = mix(nrm, vec3(0.5, 0.5, 1.0), (body + frame) * 0.75);
			}
		}
		// Gully grates on the carriageway side of the edge line.
		float gc = floor(along / 24.0);
		if (cell_hash(gc, 7.3) < 0.85) {
			float side = cell_hash(gc, 1.9) < 0.5 ? -1.0 : 1.0;
			vec2 q = vec2(across - side * (half_w - 0.86), along - (gc + 0.5) * 24.0);
			if (abs(q.x) < 0.26 && abs(q.y) < 0.46) {
				grate = 1.0;
				float rim = max(step(0.2, abs(q.x)), step(0.4, abs(q.y)));
				float slot = step(0.55, fract(q.y / 0.07)) * (1.0 - rim) * step(abs(q.x), 0.17);
				asphalt = mix(vec3(0.034, 0.031, 0.028), vec3(0.004), slot);
				rough = mix(0.8, 0.98, slot);
				nrm = mix(nrm, vec3(0.5, 0.5, 1.0), 0.6);
			}
		}
	}

	// Zebra crossings: 0.5 m bars along the traffic, 0.5 m apart, across the
	// carriageway; a stop line 2 m before each, on the lane that meets it.
	float zebra = 0.0;
	float stop_line = 0.0;
	float no_lines = 0.0;
	// One texel of crossing_map (8 m per cell) names the crossing near this
	// stretch of lap, so a pixel evaluates at most one instead of looping.
	int ci = int(texelFetch(crossing_map, ivec2(clamp(int(along / CROSSING_CELL), 0, textureSize(crossing_map, 0).x - 1), 0), 0).r * 255.0 + 0.5) - 1;
	if (ci >= 0 && ci < crossing_count) {
		float hw2 = crossings[ci].y * 0.5;
		float dz = along - crossings[ci].x;
		dz -= track_len * round(dz / track_len);
		no_lines = max(no_lines, 1.0 - smoothstep(hw2 + 0.6, hw2 + 0.6 + aa_s, abs(dz)));
		float span = (1.0 - smoothstep(hw2 - aa_s, hw2 + aa_s, abs(dz))) * (1.0 - smoothstep(half_w - 0.7 - aa_x, half_w - 0.7 + aa_x, abs(across)));
		float bar = 1.0 - smoothstep(0.25 - aa_x, 0.25 + aa_x, abs(fract(across + 0.5) - 0.5));
		zebra = max(zebra, span * bar);
		float lane_side = across > 0.0 ? -1.0 : 1.0; // forward lane meets it at negative dz
		float sd = dz * lane_side - hw2 - 2.2;
		stop_line = max(stop_line, (1.0 - smoothstep(0.2 - aa_s, 0.2 + aa_s, abs(sd))) * step(abs(across), half_w - 0.4) * step(0.15, abs(across)));
	}
	lane_line *= 1.0 - no_lines;
	centre *= 1.0 - no_lines;

	vec3 col = asphalt;
	float mark = max(max(edge, zebra), max(max(lane_line, centre), stop_line));
	// Paint wear noise is only evaluated on the markings themselves.
	if (mark > 0.0) {
		float worn = 0.78 + 0.20 * vnoise(vec2(across, along) * 1.7);
		col = mix(col, line_white * worn, edge * 0.9);
		col = mix(col, line_white * worn, lane_line * 0.85);
		vec3 centre_tint = mix(line_yellow, line_white * vec3(0.95, 0.94, 0.9), showcase);
		col = mix(col, centre_tint * worn, centre * 0.9);
		col = mix(col, line_white * worn, max(zebra, stop_line) * 0.9);
		rough = mix(rough, 0.55, mark);
	}

	// Pale staggered stone setts through the historic Muradie street.
	if (stone_section.y > 0.0) {
		float stone_s = mod(along - stone_section.x, track_len);
		if (stone_s < stone_section.y) {
			vec2 slab_uv = vec2(across / 0.65 + mod(floor(stone_s / 0.38), 2.0) * 0.5, stone_s / 0.38);
			vec2 joints = min(fract(slab_uv), 1.0 - fract(slab_uv));
			float grout = smoothstep(0.015, 0.061, min(joints.x, joints.y));
			vec3 slab = vec3(0.56, 0.50, 0.41) * (0.88 + hash(floor(slab_uv)) * 0.22);
			float blend = smoothstep(0.0, 1.4, min(stone_s, stone_section.y - stone_s));
			col = mix(col, slab * mix(0.59, 1.0, grout), blend);
			rough = mix(rough, 0.89, blend);
			nrm = mix(nrm, vec3(0.5, 0.5, 1.0), blend * 0.72);
		}
	}

	// start / finish chequer band 6 m long
	float ds = along - start_s;
	ds = ds - track_len * floor(ds / track_len);
	if (ds < 6.0 && ds > 0.0) {
		float cx = floor(across / 1.0);
		float cy = floor(ds / 1.0);
		float chk = mod(cx + cy, 2.0);
		col = mix(col, mix(vec3(0.05), vec3(0.9), chk), 0.9);
		rough = 0.55;
	}

	// puddles: low frequency noise, concentrate near edges. A dry road skips
	// the noise entirely.
	float wet = 0.0;
	if (wetness > 0.001) {
		float pud = vnoise(vec2(across, along) * 0.11) * 0.6 + vnoise(vec2(along, across) * 0.37) * 0.4;
		float puddle = smoothstep(0.62 - 0.25 * wetness, 0.72 - 0.25 * wetness, pud) * wetness;
		puddle *= 0.5 + 0.5 * smoothstep(0.2, 0.8, abs(across) / half_w);
		wet = clamp(wetness * 0.75 + puddle, 0.0, 1.0);
		if (showcase > 0.0) {
			// Wheel paths shed water. The gutter keeps a smoother film and
			// catches sky and lamp highlights through the Mobile BRDF.
			puddle *= mix(1.0, 0.53 + 0.38 * gutter - 0.22 * wear, showcase);
			wet = clamp(wetness * (0.62 + gutter * 0.14) + puddle, 0.0, 1.0);
		}
		// Damp asphalt stays dark and textured; only puddles become smooth.
		col *= 1.0 - mix(0.40, 0.56, showcase) * wet;
		rough = mix(rough, mix(0.22, 0.31, showcase), wet);
		rough = mix(rough, 0.07, puddle);
		nrm = mix(nrm, vec3(0.5, 0.5, 1.0), puddle);
	}

	// snow slush on the sides
	if (snow > 0.001) {
		float slush = snow * smoothstep(0.55, 0.95, abs(across) / half_w);
		col = mix(col, vec3(0.85, 0.87, 0.9), slush);
		rough = mix(rough, 0.6, slush);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.66, wet * showcase);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = mix(0.45, 0.2, clamp(wet, 0.0, 1.0));
}
