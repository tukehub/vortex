extends Node3D
## Vehicle detail pass: the model keeps its size and wheel positions, the
## calipers leave the spinning wheels and steer, rims keep the shop colour,
## glass shows the cabin, lamps and halos follow night and braking, drivers
## ride in every car, contact patches sit under the tyres, wet tyres, and
## probes skip detail.

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHECK FAILED: " + message)


func _ready() -> void:
	Quality.set_preset("medium")
	var def: Dictionary = Data.CARS[0]
	var source: Node3D = (load(str(def.visual.model_path)) as PackedScene).instantiate()
	var player := CarVisual.new()
	add_child(player)
	player.setup(def, Color.html(str(def.color)), true, {"rim": "gold"})
	var bot := CarVisual.new()
	add_child(bot)
	bot.setup(def, Color("2f7bff"), false)

	# Dimensions and wheel positions are the model's own.
	for nm in ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]:
		var src: Node3D = source.get_node(nm)
		check(player.wheels[nm].position.is_equal_approx(src.position), "%s stays where the model puts it" % nm)
	check(player.body.mesh.get_aabb().is_equal_approx((source.get_node("body") as MeshInstance3D).mesh.get_aabb()), "body bounds unchanged")
	check(is_equal_approx(player.visual_wheel_radius, (source.get_node("wheel_rl") as MeshInstance3D).mesh.get_aabb().size.y * 0.5), "wheel radius unchanged")

	# Calipers: out of the wheels, one mesh, behind every axle, front ones steer.
	check(player.calipers != null and player.calipers.get_parent() == player.model, "calipers are one mesh on the car")
	for w: MeshInstance3D in player.wheels.values():
		var names := []
		for i in w.mesh.get_surface_count():
			names.append(w.mesh.surface_get_material(i).resource_name)
		check(not "trim" in names and "rim" in names and "tyre" in names, "%s spins rim and tyre only" % w.name)
	var caliper_mesh := player.calipers.mesh as ArrayMesh
	var verts: PackedVector3Array = caliper_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = caliper_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	# Each caliper stays where its wheel drew it: inside the wheel, at the
	# disc's radius from the axle.
	var sums := {}
	var fronts := 0
	for i in verts.size():
		var key := Vector2i(signi(int(signf(verts[i].x))), 1 if colors[i].r > 0.5 else 0)
		if not sums.has(key):
			sums[key] = [Vector3.ZERO, 0]
		sums[key][0] += verts[i]
		sums[key][1] += 1
		fronts += 1 if colors[i].r > 0.5 else 0
	check(sums.size() == 4, "four calipers")
	for key: Vector2i in sums:
		var centre: Vector3 = sums[key][0] / float(sums[key][1])
		var axle: Vector3 = (player.wheels.wheel_fl if key.y == 1 else player.wheels.wheel_rl).position
		var off := Vector2(centre.y - axle.y, centre.z - axle.z).length()
		check(off > 0.08 and off < 0.26, "caliper %s grips its disc, %.2f m from the axle" % [key, off])
		check(absf(absf(centre.x) - absf(axle.x)) < 0.15, "caliper %s sits inside its wheel" % key)
	check(fronts * 2 == verts.size(), "half the caliper vertices steer")
	var state := CarState.new(0, def, "test", true, Color.WHITE)
	var track := RaceTrack.load_city("tirane")
	state.v = 12.0
	state.steer = 1.0
	player.apply_state(state, track, 0.3)
	check(absf(player.steer_vis) > 0.001 and is_equal_approx(float(player.caliper_material.get_shader_parameter("steer")), player.steer_vis), "front calipers follow the steering")

	# Rims keep the shop colour on the new wheel shader.
	var gold := Color.html(str(Data.shop_item("rim", "gold").color))
	var rim_mat := player.wheels.wheel_fl.get_surface_override_material(1) as ShaderMaterial
	check(rim_mat != null and (rim_mat.get_shader_parameter("rim_color") as Color).is_equal_approx(gold), "the chosen rim colour drives the wheel shader")

	# Paint stays customisable and reads as a clear-coated metallic.
	check(player.mat_paint.albedo_color.is_equal_approx(Color.html(str(def.color)).darkened(0.30)) or player.mat_paint.albedo_color.s < 0.2, "paint colour still comes from the car's colour")
	check(is_equal_approx(bot.mat_paint.albedo_color.h, Color("2f7bff").darkened(0.3).h), "a rival's paint keeps its own colour")
	check(player.mat_paint.clearcoat >= 0.99 and player.mat_paint.clearcoat_roughness < 0.1 and player.mat_paint.roughness >= 0.3, "clear coat over a satin base coat, not a mirror")

	# Glass: transparent with full reflections; drivers in every car.
	var glass := player.finish_glass
	check(glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and glass.blend_mode == BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA, "glass keeps its reflections while transparent")
	check(glass.albedo_color.a > 0.4 and glass.albedo_color.a < 0.7, "tinted, not clear and not opaque")
	check(player.finish_driver != null and bot.finish_driver != null, "every car has a driver behind the glass")

	# Lamps and halos: day, night, braking.
	player.set_night(0.0)
	check(float(player.lamp_front.get_shader_parameter("running")) > 0.0 and is_zero_approx(float(player.lamp_front.get_shader_parameter("beam"))), "daytime running lights, no beam by day")
	check(not player.halos[0].visible and not player.halos[2].visible, "no halos in daylight at rest")
	state.braking = true
	player.apply_state(state, track, 0.016)
	check(float(player.lamp_rear.get_shader_parameter("beam")) >= CarVisual.BRAKE and player.halos[2].visible, "brake lights and their glow come on")
	state.braking = false
	state.v = 12.0
	player.apply_state(state, track, 0.016)
	check(is_zero_approx(float(player.lamp_rear.get_shader_parameter("beam"))) and not player.halos[2].visible, "and go off")
	player.set_night(1.0)
	check(float(player.lamp_front.get_shader_parameter("beam")) > 0.0 and player.halos[0].visible and player.halos[2].visible, "night: dipped beams, head and tail glow")
	check(player.head_l.visible and is_equal_approx(player.head_l.light_energy, CarVisual.HEADLIGHT_ENERGY) and player.head_l.light_projector == null, "the player's beams light the road (no projector: Mobile draws none)")
	for halo in player.halos:
		check(halo.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and halo.get_parent() == player.model, "halos cast nothing and blink with the car")

	# Contact patches under this model's tyres.
	var contact := player.contact_shadow.material_override as ShaderMaterial
	var tyres: PackedVector2Array = contact.get_shader_parameter("tyres")
	check(tyres.size() == 4 and tyres[0].is_equal_approx(Vector2(player.wheels.wheel_fl.position.x, player.wheels.wheel_fl.position.z)), "contact patches sit under the tyres")

	# Wet tyres; probes skip street detail.
	CarVisual.set_wet(1.0)
	var tyre := player.wheels.wheel_fl.get_surface_override_material(0) as ShaderMaterial
	check(is_equal_approx(float(tyre.get_shader_parameter("wetness")), 1.0), "rain wets the tyres")
	CarVisual.set_wet(0.0)
	check(RaceReflections.PROBE_MASK & (1 << (RaceReflections.DETAIL_LAYER - 1)) == 0, "probes skip the detail layer")
	var prop := MeshInstance3D.new()
	add_child(prop)
	RaceReflections.hide_detail(prop)
	check(prop.layers & RaceReflections.PROBE_MASK == 0 and prop.layers != 0, "detail stays visible to cameras, not to probes")
	check(int(ProjectSettings.get_setting("rendering/reflections/reflection_atlas/reflection_count")) >= Quality.REFLECTION_PROBES_PER_MESH + 1, "the atlas holds every probe a race and the garage use")
	source.free()
	player.queue_free()
	bot.queue_free()
	await get_tree().process_frame
	print("CAR DETAIL: failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
