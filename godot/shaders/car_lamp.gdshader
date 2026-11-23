shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// The public car's lamp clusters, by body-local position within the lamp's
// own bounds (`lamp_min`, `lamp_size`): `rear` = the full-width LED tail bar
// in segments, brighter towards its ends; front = clear lenses over a chrome
// reflector with a daytime-running-light strip along the top and a
// projector eye in each half, lit as dipped beams at night.
uniform bool rear = false;
uniform vec3 lamp_min = vec3(-0.7, 0.62, -2.03);
uniform vec3 lamp_size = vec3(1.4, 0.07, 0.18);
uniform vec4 lamp_color : source_color = vec4(1.0, 0.95, 0.9, 1.0);
// Running light (DRL / tail) and the main beam (dipped beam / brake).
uniform float running : hint_range(0.0, 8.0) = 1.0;
uniform float beam : hint_range(0.0, 8.0) = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 uv = (lp.xy - lamp_min.xy) / lamp_size.xy;
	float side_u = fract(uv.x * 2.0);          // 0..1 across each half
	vec3 col;
	vec3 glow;
	if (rear) {
		// LED segments 2.3 cm apart, fading to their average far away.
		float seg_u = uv.x * 60.0;
		float aa = max(fwidth(seg_u), 1e-4);
		float led = mix(0.75, 1.0 - smoothstep(0.32, 0.32 + aa, abs(fract(seg_u) - 0.5)), 1.0 - smoothstep(0.2, 0.6, aa));
		float ends = smoothstep(0.32, 0.42, abs(uv.x - 0.5));
		float tail = running * mix(0.55, 1.0, ends);
		col = vec3(0.1, 0.004, 0.003);
		glow = lamp_color.rgb * led * (tail + beam);
		ROUGHNESS = 0.12;
	} else {
		float drl = smoothstep(0.66, 0.74, uv.y);
		vec2 eye = vec2(side_u - (lp.x > 0.0 ? 0.32 : 0.68), (uv.y - 0.4) * lamp_size.y / (lamp_size.x * 0.5));
		float projector = 1.0 - smoothstep(0.07, 0.11, length(eye));
		col = mix(vec3(0.45, 0.47, 0.5), vec3(0.8), projector);
		glow = lamp_color.rgb * (drl * running + projector * (beam + running * 0.25));
		METALLIC = 0.9 * (1.0 - drl);
		ROUGHNESS = 0.08;
	}
	ALBEDO = col;
	EMISSION = glow;
}
