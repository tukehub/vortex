extends Node3D
## Plan 3.3: the follow probe, landmark probes, their budget, the garage's
## HDRI/probe/glossy floor and the lower ambient fill where a probe lights.

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHECK FAILED: " + message)


func _ready() -> void:
	Settings.adaptive_quality = false
	Quality.configure_from_settings()
	# Budget: low has none, medium a follow probe, high adds landmark probes,
	# and every tier fits Mobile's per-mesh probe ceiling.
	for preset in ["low", "medium", "high"]:
		Quality.set_preset(preset)
		for stage in 4:
			Quality.set_pressure_stage(stage)
			var probes := (1 if Quality.p.probe else 0) + int(Quality.p.landmark_probes)
			check(probes <= Quality.REFLECTION_PROBES_PER_MESH, "probes fit the per-mesh ceiling on %s/%d" % [preset, stage])
			check(bool(Quality.p.probe) == (preset != "low" and stage < 3), "follow probe on medium/high until the last pressure stage (%s/%d)" % [preset, stage])
			check((int(Quality.p.landmark_probes) > 0) == (preset == "high" and stage < 2), "landmark probes only on unpressured high (%s/%d)" % [preset, stage])
	check(RaceReflections.MAX_LANDMARK_PROBES + 1 <= Quality.REFLECTION_PROBES_PER_MESH, "the most probes ever built fit one mesh")

	# The race scene on high: one follow probe, landmark probes beside the road.
	Quality.set_preset("high")
	Game.race_opts.city = "tirane"
	Game.race_opts.env = "day"
	Game.race_opts.laps = 1
	var scene := RaceScene.new()
	add_child(scene)
	scene.set_process(false)
	var refl := scene.reflections
	check(refl != null and refl.follow != null, "race builds a follow probe")
	check(refl.follow.update_mode == ReflectionProbe.UPDATE_ONCE, "follow probe renders only when it moves")
	check(refl.landmark_probes.size() == RaceReflections.MAX_LANDMARK_PROBES, "Tirana gets every landmark probe on high (%d)" % refl.landmark_probes.size())
	for probe in refl.landmark_probes:
		check(probe.visible and probe.box_projection, "landmark probes are box-projected and shown on high")
		var road := scene.track.nearest(probe.position.x, probe.position.z, RaceReflections.LANDMARK_REACH)
		check(road >= 0, "each landmark probe sits near the circuit")
	for i in refl.landmark_probes.size():
		for j in range(i + 1, refl.landmark_probes.size()):
			check(refl.landmark_probes[i].position.distance_to(refl.landmark_probes[j].position) >= RaceReflections.LANDMARK_SIZE.x * 0.5, "landmark probes do not stack")

	# Cars stay out of every probe: the player on PLAYER_LAYER, bots on CAR_LAYER.
	var player_index := scene.race.cars.find(scene.player)
	for i in scene.cars.size():
		for node in scene.cars[i].find_children("*", "GeometryInstance3D", true, false):
			var layers := (node as GeometryInstance3D).layers
			check(layers & RaceReflections.PROBE_MASK == 0, "car %d mesh %s is invisible to probes" % [i, node.name])
			check(layers != 0, "car meshes stay visible to the race camera")
	check(scene.cam.cull_mask & (1 << (RaceReflections.CAR_LAYER - 1)) != 0, "the race camera still draws the bots")
	check(scene.views.rear.cull_mask & (1 << (RaceReflections.CAR_LAYER - 1)) != 0, "the mirror still draws the bots")
	check(refl.follow.cull_mask == RaceReflections.PROBE_MASK, "follow probe sees the world only")
	check(player_index >= 0, "player found")

	# Following: one move to start, none while within a step, one per step after.
	var track := scene.track
	var s := 300.0
	refl.update_focus(track.pos(s, 0.0), track.tangent(s))
	check(refl.follow.visible and refl.follow_moves == 1, "first frame places the follow probe")
	var first := refl.follow.position
	check(first.y > track.height(s) + 1.0, "follow probe floats above the road")
	check(Vector2(first.x, first.z).distance_to(Vector2(track.pos(s, 0.0).x, track.pos(s, 0.0).z)) > 1.0, "follow probe lands ahead of the car")
	for k in 20:
		var at := s + k * 0.5
		refl.update_focus(track.pos(at, 0.0), track.tangent(at))
	check(refl.follow_moves == 1, "small moves do not re-render the probe")
	var step := float(Quality.p.probe_step)
	var moves_before := refl.follow_moves
	var distance := 0.0
	while distance < step * 12.0:
		distance += 1.0
		refl.update_focus(track.pos(s + distance, 0.0), track.tangent(s + distance))
	var moves := refl.follow_moves - moves_before
	check(moves >= 6 and moves <= 12, "one re-render every one to two steps (%d over %d m)" % [moves, int(distance)])

	# Budget changes toggle the same probes, never build new ones.
	var ids := [refl.follow.get_instance_id()]
	for probe in refl.landmark_probes:
		ids.append(probe.get_instance_id())
	Quality.set_preset("medium")
	check(refl.follow.visible, "medium keeps the follow probe")
	for probe in refl.landmark_probes:
		check(not probe.visible, "medium hides landmark probes")
	Quality.set_preset("low")
	check(not refl.follow.visible, "low hides the follow probe")
	Quality.set_preset("high")
	Quality.set_pressure_stage(3)
	check(not refl.follow.visible, "the last pressure stage drops the follow probe")
	Quality.set_pressure_stage(0)
	var after := [refl.follow.get_instance_id()]
	for probe in refl.landmark_probes:
		after.append(probe.get_instance_id())
		check(probe.visible, "high shows landmark probes again")
	check(after == ids, "budget changes reuse the same probes")

	# Restart keeps the probes and hides the new bots from them as well.
	scene.restart()
	await get_tree().process_frame
	check(scene.reflections == refl and refl.follow.get_instance_id() == ids[0], "restart keeps the world's probes")
	for i in scene.cars.size():
		for node in scene.cars[i].find_children("*", "GeometryInstance3D", true, false):
			check((node as GeometryInstance3D).layers & RaceReflections.PROBE_MASK == 0, "restarted cars stay invisible to probes")

	# Ambient: probe tiers take 15% off the flat fill and lower its floor.
	Quality.set_preset("high")
	scene.sky.apply("day")
	var lit := scene.sky.env.ambient_light_energy
	Quality.set_preset("low")
	var flat := scene.sky.env.ambient_light_energy
	check(lit < flat, "probe tiers use a lower flat ambient (%.2f < %.2f)" % [lit, flat])
	check(is_equal_approx(flat, maxf(float(Data.ENV.day.ambient), 0.45)), "low keeps the old ambient floor")
	check(SkyEnv.ambient_energy(0.1, false, true) >= 0.36 and SkyEnv.ambient_energy(0.1, true, true) >= 0.42, "probe tiers still keep a visibility floor")
	check(SkyEnv.ambient_energy(0.1, true, false) == 0.48, "night without a probe keeps 0.48")
	scene.queue_free()
	await get_tree().process_frame

	# Garage: HDRI background, a box-projected probe that ignores the car, a glossy floor.
	Quality.set_preset("medium")
	var menu := Menu.new()
	add_child(menu)
	check(menu.garage_env.background_mode == Environment.BG_SKY and menu.garage_env.sky.sky_material is PanoramaSkyMaterial, "garage has an HDRI background")
	check((menu.garage_env.sky.sky_material as PanoramaSkyMaterial).panorama != null, "garage HDRI loads")
	check(menu.garage_env.ssr_enabled == bool(Quality.p.ssr), "garage floor mirror follows the renderer's SSR budget")
	check(menu.garage_probe != null and menu.garage_probe.visible and menu.garage_probe.box_projection, "garage has a box-projected probe")
	var floor_mesh := menu.get_node("GarageFloor") as MeshInstance3D
	var floor_mat := floor_mesh.material_override as StandardMaterial3D
	check(floor_mat.roughness <= 0.15, "garage floor is glossy")
	for node in menu.garage_car.find_children("*", "GeometryInstance3D", true, false):
		check((node as GeometryInstance3D).layers & menu.garage_probe.cull_mask == 0, "the turning garage car is not baked into its probe")
	menu.queue_free()
	await get_tree().process_frame
	Quality.set_preset("medium")
	print("REFLECTIONS: renderer=%s; failures=%d" % [Quality.renderer, failures])
	get_tree().quit(1 if failures else 0)
