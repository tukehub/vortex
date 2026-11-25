// Linear colours shared by the terrain and the Uji i Ftohtë cut.
const vec3 COAST_LIMESTONE = vec3(.40, .379, .334);
const vec3 COAST_TERRA_ROSSA = vec3(.255, .107, .055);
const vec3 COAST_MAQUIS = vec3(.135, .161, .066);

vec3 coastal_soil(float cover) {
	return mix(COAST_TERRA_ROSSA, COAST_MAQUIS, smoothstep(.25, .69, cover) * .55);
}
