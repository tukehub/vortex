shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// A large flag in a steady sea breeze (the great flag on Sheshi i Flamurit).
// The cloth is a plane in XY, hoist at local x = 0, fly along +x, top at
// y = 0 and hem at y = -height. Folds travel from the hoist to the fly and
// grow toward it; the fly sags a little, the cloth takes up its own width
// where it folds, and the normal follows the folds so they catch the light.

uniform sampler2D flag_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float width = 11.2;
uniform float height = 8.0;
uniform float wind = 1.0;
// Per-flag phase so neighbouring flags do not move in step.
uniform float phase = 0.0;

varying float v_fold;

// Displacement across the cloth (local z, m) at fly distance x, drop y (m).
// Folds are about two thirds of the fly long and ripple faster on a small
// flag; they reach about a fifteenth of the fly at the free edge.
float fold(float x, float y, float t) {
	float u = x / width;
	float v = -y / width;
	float pace = sqrt(8.0 / max(width, 0.5));
	float grip = smoothstep(0.0, 0.3, u) * (0.3 + 0.7 * u);
	float w = 0.0;
	w += sin(u * 9.8 - t * 2.6 * pace + v * 1.1) * 0.58;
	w += sin(u * 17.5 - t * 4.0 * pace - v * 2.6 + 1.7) * 0.27;
	w += sin(u * 31.0 - t * 6.1 * pace + v * 4.5 + 0.4) * 0.11 * u;
	// Gusts swell and settle every few seconds.
	float gust = 0.78 + 0.22 * sin(t * 0.37 + 0.8) * sin(t * 0.23);
	return w * grip * gust * wind * width * 0.085;
}

void vertex() {
	float t = TIME + phase * 6.2832;
	float x = VERTEX.x;
	float y = VERTEX.y;
	float z = fold(x, y, t);
	float e = 0.02 * width;
	float dzdx = (fold(x + e, y, t) - fold(x - e, y, t)) / (2.0 * e);
	float dzdy = (fold(x, y + e, t) - fold(x, y - e, t)) / (2.0 * e);
	float u = x / width;
	// Folded cloth is shorter along the fly; the fly droops and lifts.
	float slack = 1.25 - 0.45 * clamp(wind, 0.0, 1.5);
	VERTEX.x = x - u * u * 0.05 * width * wind - 0.10 * abs(z) * u;
	VERTEX.y = y - u * u * width * (0.035 + 0.018 * sin(t * 0.9 - y * 0.4)) * slack;
	VERTEX.z = z;
	NORMAL = normalize(vec3(-dzdx, -dzdy, 1.0));
	v_fold = clamp(dzdx * 1.6, -1.0, 1.0);
}

void fragment() {
	vec3 cloth = texture(flag_tex, UV).rgb;
	// Troughs facing away from the breeze sit in their own shade.
	float shade = 1.0 - 0.16 * smoothstep(0.1, 0.9, abs(v_fold));
	ALBEDO = cloth * shade;
	ROUGHNESS = 0.74;
	SPECULAR = 0.32;
	// Woven polyester: a faint sheen along the folds, and light through it.
	RIM = 0.18;
	RIM_TINT = 0.6;
	BACKLIGHT = cloth * 0.45;
}
