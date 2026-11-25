#include "res://shaders/coastal_palette.gdshaderinc"

const vec3 COAST_MEAN[4] = {
	vec3(.429,.306,.201), vec3(.132,.046,.024),
	vec3(.330,.175,.084), vec3(.232,.163,.096)
};
const float COAST_TILE[4] = {2.85, 2.6, 1.85, 2.25};

struct CoastGround {
	vec3 albedo;
	vec3 detail_normal;
	float roughness;
	float ao;
};

void coast_add(inout CoastGround result, inout float total, float coverage, float height,
		vec3 albedo, vec2 normal_xy, float roughness, float ao) {
	// High points win gently where materials meet, leaving recesses for finer
	// soil or sediment. A masked layer cannot bleed past its spatial boundary.
	float weight = coverage * exp2((height - .5) * 2.9);
	result.albedo += albedo * weight;
	result.detail_normal += vec3(normal_xy.x, 0., normal_xy.y) * weight;
	result.roughness += roughness * weight;
	result.ao += ao * weight;
	total += weight;
}

CoastGround coastal_surface(vec3 world, vec3 n, float distance_m, vec4 paint,
		vec2 geomorph, vec2 shore, float above, out float limestone_weight) {
	vec2 xz = world.xz;
	vec3 dx = dFdx(world);
	vec3 dy = dFdy(world);
	vec3 land = texture(ground_macro, xz / 1580.).rgb;
	vec2 turned = vec2(.78*xz.x - .63*xz.y, .63*xz.x + .78*xz.y);
	vec3 breakup = texture(ground_macro, turned / 543. + vec2(.21,.67)).gbr;
	float patch = mix(land.b, breakup.r, .39);
	float sheltered = smoothstep(.28,.69, land.r + (breakup.g-.5)*.28 + paint.g*.20);
	float slope = 1.0 - n.y;
	float upland = smoothstep(17., 100., above);
	float gully = smoothstep(.05, .79, geomorph.y);
	float exposure = slope * 1.85 + (land.g-.53)*.58 + (patch-.5)*.30
		+ upland*.10 + (smoothstep(.04,.76,geomorph.x))*.49 + abs(n.x)*.055;
	limestone_weight = smoothstep(.19,.68, exposure - gully*.10);
	float rock = limestone_weight;
	float bank = (1. - smoothstep(15.,35.,shore.x)) * (1. - smoothstep(2.0,6.6,above)) * shore.y;
	bank *= (1. - smoothstep(.14,.35,slope)) * (1. - smoothstep(.26,.70,paint.r));
	bank *= (1. - rock);
	// Washed shingle follows elevation and distance from the sea. Gravel
	// collects just above it, at road edges and in the baked drainage cuts.
	float wash = (1. - smoothstep(1.4,4.2,above)) * smoothstep(.32,.69,patch + (1.-smoothstep(2.,18.,shore.x))*.21);
	float pebbles = bank * wash;
	float sand = bank - pebbles;
	float inland = max(0., 1. - rock - bank);
	float shoulder = smoothstep(.04,.21,paint.r) * (1. - smoothstep(.39,.68,paint.r));
	float fan = (1. - smoothstep(.12,.34,slope)) * gully * .54;
	float gravel = inland * clamp(shoulder*.88 + fan
		+ smoothstep(.62,.77, patch + upland*.045)*.34
		+ bank*smoothstep(.8,3.2,above)*.10, 0., .92);
	float grass = (inland-gravel) * clamp(.18 + sheltered*.72 + upland*.06 - gully*.37, .04, .94);
	float soil = inland-gravel-grass;
	vec4 weights = vec4(grass,soil,gravel,pebbles);

	float tone = .74 + land.b*.31 + breakup.b*.20;
	vec3 dry_grass = mix(vec3(.253,.206,.078), COAST_MAQUIS, sheltered*.78);
	vec3 red_soil = coastal_soil(land.r) * mix(1.,.81,gully);
	vec3 grit = mix(vec3(.31,.249,.162), vec3(.25,.213,.174),land.g);
	vec3 shingle = vec3(.34,.294,.237);
	vec3 colours[4] = {dry_grass,red_soil,grit,shingle};
	const vec4 baseline_roughness = vec4(.93,.85,.76,.71);
	float wash_wet = (1. - smoothstep(.08, .83, above)) * (1. - smoothstep(3.,12.,shore.x));
	float damp = clamp(wash_wet*.87 + gully*(.17+wetness*.33),0.,.91);
	// Wet sediment and pebbles differ from pulverized limestone and straw.
	colours[1] *= mix(1., .78, gully*.55);
	colours[3] *= mix(1., .54, damp);
	vec3 dune = sand_color * mix(.78, .53, wash_wet);
	vec3 stone = COAST_LIMESTONE * mix(.72,1.15,land.g*.67 + breakup.b*.33);
	CoastGround macro = CoastGround(
		(colours[0]*grass + colours[1]*soil + colours[2]*gravel + colours[3]*pebbles
			+ stone*rock + dune*sand)*tone, vec3(0.),
		dot(weights,baseline_roughness) + .82*rock + mix(.90,.52,wash_wet)*sand - pebbles*damp*.18,
		1. - gully*.11);
	// Distances change cost, while the same world-space masks and palette
	// continue from the foreground to the skyline.
	float scale = two_scale ? 1. : .61;
	float detail = 1. - smoothstep(72.*scale, 242.*scale,distance_m);
	float micro = two_scale ? (1. - smoothstep(22., 79., distance_m)) : 0.;
	if (detail <= .001) {
		return macro;
	}

	// Explicit gradients keep mip selection stable when neighbouring
	// fragments choose different material layers.
	vec2 bend = (vec2(land.b, breakup.g) - .5) * 5.3;
	CoastGround close = CoastGround(vec3(0.),vec3(0.),0.,0.);
	float total = 0.;
	for (int i = 0; i < 4; i++) {
		float w = weights[i] * smoothstep(.008,.055,weights[i]);
		if (w > .001) {
			float tile = COAST_TILE[i];
			vec3 uv = vec3((xz+bend) / tile, float(i));
			vec3 photo = textureGrad(ground_layers, uv, dx.xz / tile, dy.xz / tile).rgb;
			vec4 pbr = textureGrad(ground_layers_pbr, uv, dx.xz / tile, dy.xz / tile);
			photo = clamp(photo / COAST_MEAN[i], .39, 1.67);
			float r = mix(baseline_roughness[i],pbr.b,.40);
			if (i == 3) { r -= damp*.22; }
			coast_add(close,total,w,pbr.a,colours[i] * mix(vec3(1.),photo,.72),
				(pbr.rg*2.-1.) * micro*.52,r,1.);
		}
	}
	if (rock > .01) {
		vec3 p = world + vec3(bend.x, 0., bend.y);
		const float tile = 4.9;
		vec2 uv = p.xz / tile;
		vec3 photo = textureGrad(tex_rock,uv,dx.xz/tile,dy.xz/tile).rgb;
		vec3 arm = textureGrad(tex_limestone_arm,uv,dx.xz/tile,dy.xz/tile).rgb;
		float tri = smoothstep(.14,.37,slope);
		vec3 axes = pow(abs(n),vec3(4.));
		axes /= dot(axes,vec3(1.));
		if (tri > .02) {
			vec3 x_face = textureGrad(tex_rock,p.zy/tile,dx.zy/tile,dy.zy/tile).rgb;
			vec3 z_face = textureGrad(tex_rock,p.xy/tile,dx.xy/tile,dy.xy/tile).rgb;
			photo = mix(photo, x_face*axes.x + photo*axes.y + z_face*axes.z, tri);
			if (axes.x > max(axes.y,axes.z)) {
				arm = textureGrad(tex_limestone_arm,p.zy/tile,dx.zy/tile,dy.zy/tile).rgb;
			} else if (axes.z > axes.y) {
				arm = textureGrad(tex_limestone_arm,p.xy/tile,dx.xy/tile,dy.xy/tile).rgb;
			}
		}
		vec3 delta = vec3(0.);
		if (micro > .01) {
			vec2 top = textureGrad(tex_rock_n,uv,dx.xz/tile,dy.xz/tile).rg*2.-1.;
			delta = vec3(top.x,0.,top.y);
			if (tri > .02) {
				vec2 side_x = textureGrad(tex_rock_n,p.zy/tile,dx.zy/tile,dy.zy/tile).rg*2.-1.;
				vec2 side_z = textureGrad(tex_rock_n,p.xy/tile,dx.xy/tile,dy.xy/tile).rg*2.-1.;
				delta = mix(delta,vec3(0.,side_x.y,side_x.x)*axes.x
					+ delta*axes.y + vec3(side_z.x,side_z.y,0.)*axes.z,tri);
			}
		}
		float luminance = dot(photo, vec3(.24,.62,.14));
		float height = clamp(.43 + (luminance-.164)*1.36 + geomorph.x*.22, 0., 1.);
		vec3 tinted = stone * mix(vec3(1.),clamp(photo/vec3(.236,.146,.082),.41,1.75),.65);
		coast_add(close,total,rock,height,tinted,vec2(0.),mix(.83,arm.g,.47),mix(.78,1.,arm.r));
		close.detail_normal += delta * rock * micro * .42;
	}
	if (sand > .01) {
		vec2 uv = (xz+bend) / SAND_TILE;
		vec3 photo = textureGrad(tex_sand,uv,dx.xz/SAND_TILE,dy.xz/SAND_TILE).rgb;
		vec3 arm = textureGrad(tex_sand_arm,uv,dx.xz/SAND_TILE,dy.xz/SAND_TILE).rgb;
		vec2 fine = vec2(0.);
		if (micro > .01) {
			fine = (textureGrad(tex_sand_n,uv,dx.xz/SAND_TILE,dy.xz/SAND_TILE).rg*2.-1.)*micro*.33;
		}
		coast_add(close,total,sand,.41,dune*mix(vec3(1.),clamp(photo/SAND_MEAN,.55,1.60),.49),
			fine,mix(arm.g,.49,wash_wet),arm.r);
	}
	float resolve = detail * step(.05,total);
	float norm = 1. / max(.05,total);
	return CoastGround(mix(macro.albedo,close.albedo*norm*tone,resolve),
		close.detail_normal*norm*resolve,mix(macro.roughness,close.roughness*norm,resolve),
		mix(macro.ao,close.ao*norm,resolve));
}
