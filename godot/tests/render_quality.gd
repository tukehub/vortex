extends Node3D
## Android graphics pass: sharper medium (0.9 scale, MSAA 2x, mip bias),
## the player's sun shadow on medium, sky-tinted daylight fill, glow only
## where it shows, and the road's one-fetch crossing lookup.

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHECK FAILED: " + message)


func _ready() -> void:
	Settings.adaptive_quality = false
	Quality.configure_from_settings()
	# Presets and their pressure fallbacks.
	Quality.set_preset("medium")
	check(is_equal_approx(float(Quality.p.scale), 0.9), "medium renders 3D at 0.9")
	check(Quality.p.msaa == Viewport.MSAA_2X and not Quality.p.fxaa, "medium resolves edges with MSAA 2x, no FXAA blur")
	check(float(Quality.p.mip_bias) < 0.0, "medium sharpens textures to offset its reduced scale")
	Quality.apply_viewport(get_viewport())
	check(is_equal_approx(get_viewport().texture_mipmap_bias, float(Quality.p.mip_bias)), "the viewport gets the mip bias")
	check(get_viewport().msaa_3d == Viewport.MSAA_2X and get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "the viewport gets medium's AA")
	for stage in 4:
		Quality.set_pressure_stage(stage)
		check(float(Quality.p.scale) >= 0.6 - 0.0001, "scale never drops under the readability floor")
		if stage >= 2:
			check(Quality.p.msaa == Viewport.MSAA_DISABLED and Quality.p.fxaa, "stage %d trades MSAA for FXAA" % stage)
			check(float(Quality.p.mip_bias) >= -0.2, "stage %d eases the mip bias" % stage)
	Quality.set_pressure_stage(0)
	Quality.set_preset("low")
	check(Quality.p.fxaa and Quality.p.msaa == Viewport.MSAA_DISABLED and is_equal_approx(float(Quality.p.scale), 0.7), "low keeps 0.7 with FXAA")
	check(not Quality.p.player_shadow, "low casts no car sun shadows")
	Quality.set_preset("high")
	check(Quality.p.msaa == Viewport.MSAA_2X and is_equal_approx(float(Quality.p.scale), 1.0), "high stays native with MSAA 2x")
	var snap := Quality.snapshot()
	check(snap.has("msaa") and snap.has("fxaa") and snap.has("mip_bias") and snap.has("player_shadow"), "PROFILE reports the AA and shadow budget")
	if Quality.renderer != "forward_plus":
		for key in Quality.FORWARD_PLUS_ONLY:
			check(not bool(Quality.p[key]), "%s stays off on the %s renderer" % [key, Quality.renderer])

	# Car shadows: high all, medium only the player, low none; the contact
	# shadow is always there.
	var cars: Array[CarVisual] = []
	for i in 2:
		var car := CarVisual.new()
		add_child(car)
		car.setup(Data.CARS[i], Color.html(Data.CARS[i].color), i == 0)
		cars.append(car)
	for preset in ["low", "medium", "high"]:
		Quality.set_preset(preset)
		for car in cars:
			car._apply_render_budget()
			var casts := _casts(car)
			var want: bool = preset == "high" or (preset == "medium" and car.is_player)
			check(casts == want, "%s: %s car casts a sun shadow = %s" % [preset, "player" if car.is_player else "bot", want])
			check(car.contact_shadow.visible, "contact shadow stays on %s" % preset)
	Quality.set_pressure_stage(2)
	Quality.set_preset("medium")
	Quality.set_pressure_stage(2)
	cars[0]._apply_render_budget()
	check(not _casts(cars[0]), "pressure stage 2 drops the player's shadow on medium")
	Quality.set_pressure_stage(0)
	for car in cars:
		car.queue_free()

	# Daylight fill and glow.
	Quality.set_preset("medium")
	var sky := SkyEnv.new()
	add_child(sky)
	sky.apply("day")
	check(sky.env.ambient_light_source == Environment.AMBIENT_SOURCE_BG and is_equal_approx(sky.env.ambient_light_sky_contribution, SkyEnv.SKY_AMBIENT), "daylight fill is part sky radiance")
	check(sky.env.glow_intensity < SkyEnv.GLOW_MIN and not sky.env.glow_enabled, "invisible daylight glow is skipped")
	check(sky.env.tonemap_mode == Environment.TONE_MAPPER_ACES, "ACES tonemapping stays")
	check(sky.env.adjustment_saturation <= 1.0 and sky.env.adjustment_contrast <= 1.02 + 0.0001, "daylight is not pushed into oversaturation")
	check(is_equal_approx(sky.sun.light_energy, float(Data.ENV.day.sun_i) * SkyEnv.DAY_SUN), "daylight sun energy")
	check(is_equal_approx(sky.env.tonemap_exposure, float(Data.ENV.day.exposure) * SkyEnv.DAY_EXPOSURE), "daylight exposure")
	sky.apply("night")
	check(is_zero_approx(sky.env.ambient_light_sky_contribution), "night keeps the flat fill that keeps it legible")
	check(sky.env.glow_enabled == bool(Quality.p.glow), "night keeps its glow")
	check(is_equal_approx(sky.env.tonemap_exposure, float(Data.ENV.night.exposure)), "night exposure unchanged")
	Quality.set_pressure_stage(1)
	check(sky.env.glow_enabled, "a budget change keeps night glow")
	Quality.set_pressure_stage(0)
	sky.apply("day")
	Quality.set_pressure_stage(1)
	check(not sky.env.glow_enabled, "a budget change does not bring back invisible glow")
	Quality.set_pressure_stage(0)
	# Weather change day -> night: the sky refreshes incrementally, the fill
	# eases from sky to flat and glow returns once it shows.
	sky.transition_to("night", 2.0)
	check(sky.env.sky.process_mode == Sky.PROCESS_MODE_INCREMENTAL, "a blending sky refreshes incrementally")
	sky.advance(1.0)
	var mid := sky.env.ambient_light_sky_contribution
	check(mid > 0.0 and mid < SkyEnv.SKY_AMBIENT, "sky share of the fill eases across the change (%.2f)" % mid)
	sky.advance(1.5)
	check(sky.env_id == "night" and sky.env.glow_enabled and is_zero_approx(sky.env.ambient_light_sky_contribution), "the change ends on night's fill and glow")
	sky.queue_free()

	# Crossing lookup: one texel per 8 m, wrap-around at the lap seam.
	var lap := 1000.0
	var marks := PackedVector2Array([Vector2(100.0, 4.0), Vector2(996.0, 4.0)])
	var img := RoadMesh.crossing_lookup(marks, lap)
	check(img.get_width() == ceili(lap / RoadMesh.CROSSING_CELL) and img.get_format() == Image.FORMAT_R8, "one R8 texel per cell")
	for s in [95.0, 100.0, 104.9]:
		check(roundi(img.get_pixel(floori(s / RoadMesh.CROSSING_CELL), 0).r * 255.0) == 1, "cell at %.0f m names the first crossing" % s)
	check(roundi(img.get_pixel(floori(300.0 / RoadMesh.CROSSING_CELL), 0).r * 255.0) == 0, "open road names none")
	check(roundi(img.get_pixel(0, 0).r * 255.0) == 2, "a crossing at the seam reaches the first cell")
	check(roundi(img.get_pixel(img.get_width() - 1, 0).r * 255.0) == 2, "and the last")
	await get_tree().process_frame
	Quality.set_preset("medium")
	print("RENDER QUALITY: renderer=%s; failures=%d" % [Quality.renderer, failures])
	get_tree().quit(1 if failures else 0)


func _casts(car: CarVisual) -> bool:
	for child in car.model.get_children():
		if child is GeometryInstance3D:
			return (child as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return false
