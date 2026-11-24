// World-space triplanar detail for meshes without UVs (vertex-coloured
// procedural geometry). The detail photograph is divided by its own mean
// colour, so it adds grain and relief while the vertex colour keeps the hue
// and brightness the mesh was tuned with.
//
// Include after declaring, in the including shader:
//   varying vec3 tp_pos;  varying vec3 tp_nrm;   (world position / normal)
// and set them in vertex():
//   tp_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
//   tp_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

vec3 tp_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

// Mean-normalised detail colour (about 1.0 on average), linear.
vec3 tp_albedo(sampler2D tex, vec3 p, vec3 w, float scale, vec3 tex_mean) {
	vec3 c = texture(tex, p.zy * scale).rgb * w.x
		+ texture(tex, p.xz * scale).rgb * w.y
		+ texture(tex, p.xy * scale).rgb * w.z;
	return c / tex_mean;
}

// World normal perturbed by an OpenGL (+Y) normal map, whiteout blend per axis.
vec3 tp_normal(sampler2D tex, vec3 p, vec3 n, vec3 w, float scale, float strength) {
	vec3 tx = texture(tex, p.zy * scale).rgb * 2.0 - 1.0;
	vec3 ty = texture(tex, p.xz * scale).rgb * 2.0 - 1.0;
	vec3 tz = texture(tex, p.xy * scale).rgb * 2.0 - 1.0;
	tx.xy *= strength; ty.xy *= strength; tz.xy *= strength;
	// Swizzle each tangent-space sample into world space for its plane.
	vec3 nx = vec3(n.x, tx.y + n.y, tx.x + n.z);
	vec3 ny = vec3(ty.x + n.x, n.y, ty.y + n.z);
	vec3 nz = vec3(tz.x + n.x, tz.y + n.y, n.z);
	return normalize(nx * w.x + ny * w.y + nz * w.z);
}

// Roughness from an ARM map's green channel.
float tp_rough(sampler2D arm, vec3 p, vec3 w, float scale) {
	return texture(arm, p.zy * scale).g * w.x
		+ texture(arm, p.xz * scale).g * w.y
		+ texture(arm, p.xy * scale).g * w.z;
}
