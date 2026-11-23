shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Wheel "rim" surface of the public car: one mesh holds the rim face, the
// barrel and the brake disc. They are told apart by wheel-local position
// (x across the wheel, +x the outer face; r from the axle), so the shop's rim
// colour and finish stay the only inputs (Data.RIMS). Constants are linear.
uniform vec4 rim_color : source_color = vec4(0.82, 0.83, 0.85, 1.0);
uniform float rim_metal = 0.8;
uniform float rim_rough = 0.25;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float r = length(lp.yz);
	vec3 col = rim_color.rgb;
	float metal = rim_metal;
	float rough = rim_rough;
	// Brake disc: the flat annulus inboard of the spokes.
	float disc = step(lp.x, -0.015) * step(-0.075, lp.x) * smoothstep(0.07, 0.08, r) * (1.0 - smoothstep(0.198, 0.206, r));
	if (disc > 0.0) {
		// Lathe grooves, faded before they are smaller than a pixel.
		float gr = r * 140.0;
		float resolve = 1.0 - smoothstep(0.25, 0.7, fwidth(gr));
		float groove = (0.5 + 0.5 * sin(gr * 6.2831853)) * resolve;
		vec3 iron = vec3(0.11, 0.105, 0.1) * (0.9 + 0.15 * groove);
		// A heat tint toward the friction ring's outer edge.
		iron = mix(iron, vec3(0.12, 0.075, 0.05), smoothstep(0.15, 0.2, r) * 0.35);
		// Cross-drilled holes in two staggered rings.
		float ang = atan(lp.y, lp.z) / 6.2831853;
		float ring = floor((r - 0.12) / 0.03);
		vec2 cell = vec2(ang * 18.0 + ring * 0.5, (r - 0.12) / 0.03);
		float hole = (1.0 - smoothstep(0.17, 0.24, length(fract(cell) - 0.5))) * step(0.12, r) * step(r, 0.18) * resolve;
		iron *= 1.0 - hole * 0.85;
		// Darker hub hat in the middle.
		iron = mix(iron, vec3(0.02, 0.02, 0.022), 1.0 - smoothstep(0.1, 0.11, r));
		col = mix(col, iron, disc);
		metal = mix(metal, 0.7, disc);
		rough = mix(rough, 0.42 + 0.12 * (1.0 - groove), disc);
	}
	// Inside of the barrel: shaded and dusty.
	float barrel = step(lp.x, -0.06) * step(0.25, r);
	col = mix(col, col * 0.42, barrel);
	rough = mix(rough, min(1.0, rough + 0.3), barrel);
	// Diamond-cut outer lip: bright, fine and fully metallic.
	float lip = step(0.06, lp.x) * smoothstep(0.296, 0.304, r);
	col = mix(col, vec3(0.62, 0.63, 0.64), lip * 0.8);
	metal = mix(metal, 1.0, lip);
	rough = mix(rough, 0.14, lip);
	// Centre cap.
	float cap = step(0.04, lp.x) * (1.0 - smoothstep(0.044, 0.05, r));
	col = mix(col, vec3(0.004), cap);
	rough = mix(rough, 0.35, cap);
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
}
