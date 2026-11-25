shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D concrete : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap, repeat_enable;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),
		mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}

void fragment() {
	vec2 uv = UV; // distance across the portal and metres above the approach
	vec3 photo = texture(concrete, uv * .42).rgb;
	float porous = noise2(uv * vec2(.92,.76));
	float torrent = noise2(vec2(uv.x * 4.7 + .12 * sin(uv.y * 1.4), uv.y * .14));
	float fine_run = noise2(vec2(uv.x * 13.0, uv.y * .30));
	// Runoff follows gravity beneath the crown and collects around the
	// construction lifts. Wheels and sea spray darken the bottom metre.
	float seep = smoothstep(.48,.80,torrent*.75 + .25*fine_run)
		* smoothstep(.75,5.9,uv.y + noise2(vec2(uv.x*1.64,0.)) * 2.75)
		* (1.0-.48*COLOR.g);
	float earth = (1.0-smoothstep(.05,1.55,uv.y + (porous-.5)*.62)) * (.42+.35*porous);
	float pour = 1.0-smoothstep(.012,.036,abs(fract((uv.y+.02*porous)/1.86+.5)-.5));
	float carbonate = smoothstep(.59,.83,torrent) * (.28 + .3*porous) * smoothstep(3.,6.1,uv.y);
	vec3 stone = mix(vec3(.255,.239,.209), photo * vec3(.95,.91,.83), .69);
	stone *= mix(vec3(1.),vec3(.44,.46,.39),seep*.72 + pour*.23);
	stone = mix(stone, vec3(.101,.082,.061), earth*.66);
	stone = mix(stone, vec3(.43,.407,.354), carbonate*.32);
	ALBEDO = stone * mix(.34,1.,COLOR.r);
	NORMAL_MAP = texture(concrete_normal, uv*.42).rgb;
	NORMAL_MAP_DEPTH = .72;
	AO = COLOR.r;
	AO_LIGHT_AFFECT = .48;
	ROUGHNESS = clamp(.87 + (.5-porous)*.11 - seep*.13 - earth*.07, .63, .96);
	SPECULAR = .29;
}
