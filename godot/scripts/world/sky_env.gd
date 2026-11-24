class_name SkyEnv
extends Node3D
## WorldEnvironment + sun + weather particles driven by Data.ENV presets.
## HDRI (CC0, Poly Haven) per preset; procedural sky as fallback.

const HDRI := {
	"night": "res://assets/hdri/sky_night.hdr",
	"dusk": "res://assets/hdri/sky_dusk.hdr",
	"sunset": "res://assets/hdri/sky_sunset.hdr",
	"day": "res://assets/hdri/sky_day.hdr",
	"golden": "res://assets/hdri/sky_golden.hdr",
	"rain": "res://assets/hdri/sky_rain_night.hdr",
	"snow": "res://assets/hdri/sky_overcast.hdr",
	"rainy": "res://assets/hdri/sky_overcast.hdr",
}

var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var rain: RainFx
var snow: GPUParticles3D
var env_id := "day"
var city_id := ""
var preset: Dictionary
var wet := 0.0
var night := 0.0
var _is_night := false
## Share of the daylight fill that comes from the sky radiance.
const SKY_AMBIENT := 0.55
## Daylight sun and exposure, against the night presets' 0.5 and 1.0.
const DAY_SUN := 0.81
const DAY_EXPOSURE := 0.96
## Glow weaker than this is not drawn at all.
const GLOW_MIN := 0.15
const TIRANA_AMBIENT := {"day": 0.44, "sunset": 0.43, "golden": 0.43, "night": 0.39, "rainy": 0.59, "rain": 0.49}


func _ready() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	add_child(sun)
	_make_weather()
	Quality.budget_changed.connect(_apply_quality)


## The flat ambient fill. Preserve phone visibility at night, but let daytime
## presets retain shade and surface detail instead of lifting every surface
## toward white. Where a reflection probe lights glossy surfaces with the
## street around them (3.3), the flat fill drops 15% and its floor with it.
static func ambient_energy(preset_ambient: float, is_night: bool, probe: bool) -> float:
	if probe:
		return maxf(preset_ambient * 0.85, 0.42 if is_night else 0.36)
	return maxf(preset_ambient, 0.48 if is_night else 0.45)


## Glow below GLOW_MIN intensity is invisible (daylight: 0.45 x 0.25), yet
## it costs a downsample chain and, on the Mobile renderer, the subpass
## post-process path. Skip it there.
func _gate_glow() -> void:
	env.glow_enabled = env.glow_enabled and env.glow_intensity >= GLOW_MIN


func _preset_ambient() -> float:
	var has_probe := bool(Quality.p.probe)
	var fill := float(preset.ambient)
	if city_id == "tirane" and has_probe:
		fill = float(TIRANA_AMBIENT.get(env_id, fill))
	return ambient_energy(fill, _is_night, has_probe)


func _apply_quality() -> void:
	if not preset.is_empty() and _transition >= 1.0:
		env.ambient_light_energy = _preset_ambient()
	Quality.apply_env(env, wet > 0.05)
	_gate_glow()
	env.volumetric_fog_enabled = env.volumetric_fog_enabled and night > 0.3
	Quality.apply_sun(sun)
	sun.light_angular_distance = (0.3 if night > 0.3 else 0.15) if bool(Quality.p.sun_penumbra) else 0.0
	if city_id == "tirane":
		_apply_tirana_shadows()


func apply(id: String, is_wet_override: bool = false) -> void:
	env_id = id
	preset = Data.ENV[id]
	# Rain and snow are dark by default; a preset may opt out for daytime rain.
	var is_night := bool(preset.stars) or bool(preset.get("dark", bool(preset.rain) or bool(preset.snow)))
	night = clampf(float(preset.win), 0.0, 1.0)
	wet = 1.0 if (bool(preset.wet) or is_wet_override) else 0.0

	# sky
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var hdri_path := _panorama_path(id)
	if hdri_path != "" and ResourceLoader.exists(hdri_path):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(hdri_path)
		pano.energy_multiplier = _sky_energy(id)
		sky.sky_material = pano
	else:
		var pm := ProceduralSkyMaterial.new()
		pm.sky_top_color = Data.col(preset.sky_top)
		pm.sky_horizon_color = Data.col(preset.sky_hor)
		pm.ground_bottom_color = Data.col(preset.ground)
		pm.ground_horizon_color = Data.col(preset.sky_hor)
		pm.sun_angle_max = 20.0
		sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_128 if Quality.preset == "low" else Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.sky_rotation = Vector3(0, _sky_yaw(id), 0)

	# A neutral fill keeps the road and car sides visible in building shadows,
	# including on low quality where there are no GI or local lamp lights.
	# Sky-only lighting made the old night preset almost black on a phone.
	# Daylight fill takes part of its colour and direction from the sky
	# radiance (bluish from above, darker from below) instead of one flat
	# colour, so shade reads as shade. Dark presets keep the flat fill
	# (sky contribution 0), which is what keeps them legible on a phone.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	env.ambient_light_color = Color(0.64, 0.70, 0.80) if is_night else Color(0.78, 0.82, 0.88)
	env.ambient_light_sky_contribution = 0.0 if is_night else SKY_AMBIENT
	_is_night = is_night
	env.ambient_light_energy = _preset_ambient()
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# tonemap + exposure
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# The brighter sun and sky fill below would push light facades into
	# clipping; a slightly lower exposure keeps their highlights.
	env.tonemap_exposure = float(preset.exposure) * (1.0 if is_night else DAY_EXPOSURE)
	env.tonemap_white = 4.0

	# bloom with neon threshold (sunlit white stays below the threshold)
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = 0.45 * float(preset.bloom)
	env.glow_strength = 1.0
	env.glow_bloom = 0.05 if is_night else 0.0
	env.glow_hdr_threshold = 1.15 if is_night else 1.7
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0

	# fog
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Data.col(preset.fog)
	env.fog_light_energy = 1.0
	env.fog_density = float(preset.fog_density) * (0.28 if is_night else 0.12)
	env.fog_sky_affect = 0.2 if is_night else 0.35
	env.fog_aerial_perspective = 0.5
	env.fog_height = -20.0
	env.fog_height_density = 0.0
	env.volumetric_fog_density = 0.003 if is_night else 0.0006
	env.volumetric_fog_albedo = Data.col(preset.fog).lightened(0.3)
	env.volumetric_fog_emission = Data.col(preset.fog) * 0.02
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.3
	env.volumetric_fog_sky_affect = 0.15

	# SSAO/SSR/SDFGI from quality
	env.ssao_radius = 1.5
	env.ssao_intensity = 0.75
	env.ssao_power = 1.1
	env.ssao_detail = 0.3
	env.ssil_enabled = false
	env.adjustment_enabled = true
	# Tried and rejected: contrast 1.04-1.06 clipped the golden sky (0.3% ->
	# 2.7% of the frame) and saturation 1.04 clipped the yellow centre line.
	# Daylight depth comes from the sky-tinted fill and the sun instead.
	env.adjustment_saturation = 1.08 if is_night else 0.98
	env.adjustment_contrast = 1.0 if is_night else 1.02
	Quality.apply_env(env, wet > 0.5)
	_gate_glow()
	# Clear daylight needs no volume pass or haze over the racing corridor.
	env.volumetric_fog_enabled = env.volumetric_fog_enabled and is_night

	# sun / moon
	var dir: Vector3 = preset.sun_dir
	sun.look_at_from_position(dir.normalized() * 100.0, Vector3.ZERO, Vector3.UP)
	sun.light_color = Data.col(preset.sun_col)
	sun.light_energy = float(preset.sun_i) * (0.5 if is_night else DAY_SUN) * (0.5 if bool(preset.moon) else 1.0)
	sun.light_indirect_energy = 1.0
	# PCSS penumbra: values >= ~0.3 smear PSSM shadows into nothing at this
	# shadow distance, so keep the sun disc small (real sun is 0.26 deg).
	# Below high quality, and on renderers without directional PCSS, the
	# penumbra search is skipped entirely.
	sun.light_angular_distance = (0.3 if is_night else 0.15) if bool(Quality.p.sun_penumbra) else 0.0
	sun.shadow_enabled = true
	sun.shadow_opacity = (0.5 if id == "rainy" else 0.78) if not is_night else 0.5
	Quality.apply_sun(sun)
	if city_id == "tirane":
		_apply_tirana_atmosphere(id)
		_apply_tirana_shadows()
		_gate_glow()

	rain.set_light(dir, sun.light_color * sun.light_energy, env.fog_light_color)
	rain.amount_ratio = 1.0
	rain.emitting = bool(preset.rain)
	snow.emitting = bool(preset.snow)
	rain.visible = rain.emitting
	snow.visible = snow.emitting


func _apply_tirana_atmosphere(id: String) -> void:
	env.ambient_light_sky_contribution = 0.34
	env.adjustment_saturation = 0.96
	env.glow_intensity *= 0.68
	env.glow_bloom *= 0.48
	env.glow_hdr_threshold = 1.35
	match id:
		"day":
			env.ambient_light_color = Color("#c5d1df")
			env.tonemap_exposure = 0.88
			sun.light_energy = 1.82
			sun.shadow_opacity = 0.89
		"sunset", "golden":
			env.ambient_light_color = Color("#c0c8dd")
			env.tonemap_exposure = 0.92
			env.fog_light_color = Color("#b4a3a2")
			env.fog_density = 0.00048
			sun.light_color = Color("#ffc68e") if id == "sunset" else Color("#ffe1b4")
			sun.shadow_opacity = 0.87
		"night":
			env.ambient_light_color = Color("#aebdd5")
			env.tonemap_exposure = 1.0
			env.fog_light_color = Color("#262f44")
			env.fog_density = 0.0007
			sun.shadow_opacity = 0.28
		"rainy", "rain":
			env.fog_light_color = Color("#88939c") if id == "rainy" else Color("#333d4b")
			env.fog_density = 0.00145 if id == "rainy" else 0.00185
			env.ambient_light_color = Color("#c6cdd3") if id == "rainy" else Color("#abb8d0")
			env.tonemap_exposure = 0.91 if id == "rainy" else 1.0
			sun.light_energy *= 0.64
			sun.shadow_opacity = 0.16


func _apply_tirana_shadows() -> void:
	sun.shadow_bias = 0.032
	sun.shadow_normal_bias = 1.15
	if Quality.renderer == "mobile" and Quality.preset == "high" and int(Quality.p.shadow_splits) > 1:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_split_1 = 0.32
		sun.directional_shadow_max_distance = minf(sun.directional_shadow_max_distance, 155.0)
		RenderingServer.directional_shadow_atlas_set_size(2048, true)


func _panorama_path(id: String) -> String:
	# Reuse the dusk panorama already in the Android package for golden hour.
	var sky_id := "golden" if city_id == "tirane" and id == "sunset" else id
	return HDRI.get(sky_id, "")


func _sky_energy(id: String) -> float:
	match id:
		"night": return 0.73 if city_id == "tirane" else 0.9
		# The overcast night sky is ~3x the clear night's mean radiance.
		"rain": return 0.18
		"snow": return 0.35
		"rainy": return 0.54 if city_id == "tirane" else 0.60
		"dusk": return 0.8
		"sunset": return 0.32 if city_id == "tirane" else 0.9
		_: return 1.0


func _sky_yaw(id: String) -> float:
	# rotate the HDRI so its sun roughly matches preset.sun_dir
	match id:
		"sunset": return deg_to_rad(110.0)
		"golden": return deg_to_rad(-70.0)
		"dusk": return deg_to_rad(-100.0)
		_: return 0.0


func _make_weather() -> void:
	rain = RainFx.new()
	add_child(rain)

	snow = GPUParticles3D.new()
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(30, 1, 30)
	sm.direction = Vector3(0, -1, 0)
	sm.spread = 25.0
	sm.initial_velocity_min = 1.5
	sm.initial_velocity_max = 3.0
	sm.gravity = Vector3(0, -1.2, 0)
	sm.turbulence_enabled = true
	sm.turbulence_noise_strength = 1.5
	sm.turbulence_noise_scale = 3.0
	sm.scale_min = 0.5
	sm.scale_max = 1.2
	snow.process_material = sm
	snow.amount = 900
	snow.lifetime = 6.0
	snow.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var flake := SphereMesh.new()
	flake.radius = 0.05
	flake.height = 0.1
	flake.radial_segments = 4
	flake.rings = 2
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.95, 0.96, 1.0, 0.9)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake.material = fm
	snow.draw_pass_1 = flake
	snow.emitting = false
	add_child(snow)


## The road under the player, so rain splashes land on it.
func set_rain_ground(origin: Vector3, tangent: Vector3) -> void:
	rain.set_ground(origin, tangent)


## Call every frame with the camera position so weather follows the player.
func follow(pos: Vector3) -> void:
	rain.global_position = pos + Vector3(0, 18, 0)
	snow.global_position = pos + Vector3(0, 14, 0)


var _transition := 1.0
var _duration := 1.0
var _from := {}
var _to := {}
var _sky_blend: ShaderMaterial


func _snapshot() -> Dictionary:
	return {"wet": wet, "night": night, "sun_color": sun.light_color,
		"sun_energy": sun.light_energy, "sun_rotation": sun.quaternion,
		"ambient": env.ambient_light_energy, "ambient_color": env.ambient_light_color,
		"exposure": env.tonemap_exposure,
		"fog_color": env.fog_light_color, "fog_density": env.fog_density,
		"glow": env.glow_intensity, "sky_ambient": env.ambient_light_sky_contribution,
		"shadow_opacity": sun.shadow_opacity}


## Smoothly changes both time of day and weather; no scene rebuild.
func transition_to(id: String, seconds: float = 18.0) -> void:
	if not Data.ENV.has(id) or _transition < 1.0 or id == env_id:
		return
	var old_id := env_id
	_from = _snapshot()
	apply(id)
	_to = _snapshot()
	_duration = maxf(seconds, 0.1)
	_transition = 0.0
	_sky_blend = ShaderMaterial.new()
	_sky_blend.shader = preload("res://shaders/sky_blend.gdshader")
	_sky_blend.set_shader_parameter("from_sky", load(_panorama_path(old_id)))
	_sky_blend.set_shader_parameter("to_sky", load(_panorama_path(id)))
	_sky_blend.set_shader_parameter("from_energy", _sky_energy(old_id))
	_sky_blend.set_shader_parameter("to_energy", _sky_energy(id))
	_sky_blend.set_shader_parameter("from_yaw", _sky_yaw(old_id))
	_sky_blend.set_shader_parameter("to_yaw", _sky_yaw(id))
	env.sky.sky_material = _sky_blend
	# The blend changes every frame: refresh the radiance map over several
	# frames instead of re-filtering all of it each frame.
	env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky_rotation = Vector3.ZERO
	advance(0.0)


func advance(dt: float) -> void:
	if _transition >= 1.0:
		return
	_transition = minf(1.0, _transition + dt / _duration)
	var k := smoothstep(0.0, 1.0, _transition)
	wet = lerpf(_from.wet, _to.wet, k)
	night = lerpf(_from.night, _to.night, k)
	sun.light_color = (_from.sun_color as Color).lerp(_to.sun_color, k)
	sun.light_energy = lerpf(_from.sun_energy, _to.sun_energy, k)
	sun.quaternion = (_from.sun_rotation as Quaternion).slerp(_to.sun_rotation, k)
	env.ambient_light_energy = lerpf(_from.ambient, _to.ambient, k)
	env.ambient_light_color = (_from.ambient_color as Color).lerp(_to.ambient_color, k)
	env.tonemap_exposure = lerpf(_from.exposure, _to.exposure, k)
	env.fog_light_color = (_from.fog_color as Color).lerp(_to.fog_color, k)
	env.fog_density = lerpf(_from.fog_density, _to.fog_density, k)
	env.glow_intensity = lerpf(_from.glow, _to.glow, k)
	env.ambient_light_sky_contribution = lerpf(_from.sky_ambient, _to.sky_ambient, k)
	env.glow_enabled = bool(Quality.p.glow)
	_gate_glow()
	if city_id == "tirane":
		sun.shadow_opacity = lerpf(_from.shadow_opacity, _to.shadow_opacity, k)
		rain.set_light(sun.global_transform.basis.z, sun.light_color * sun.light_energy, env.fog_light_color)
	env.ssr_enabled = bool(Quality.p.ssr) and wet > 0.05
	_sky_blend.set_shader_parameter("blend", k)
	rain.amount_ratio = wet
	if wet > 0.01:
		rain.emitting = true
		rain.visible = true
	if _transition >= 1.0:
		apply(env_id)
