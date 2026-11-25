extends Node3D
## Berat review captures (needs Vulkan; lavapipe works). Not in run_tests.
##   SHOTS=/abs/dir godot --path godot --rendering-method mobile \
##       --resolution 1280x720 res://tests/berat_visual.tscn
## Writes berat_<view>.png: the grid, Mangalem and the castle across the
## Osum from Gorica, the houses close up from both banks, Ura e Goricës, the
## castle walls, the river and the race's bridges. VIEWS=a,b limits the run
## to views whose names start with those prefixes; ENV=night etc.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sfx.enabled = false
	Quality.adaptive_enabled = false
	Quality.set_preset(OS.get_environment("QUALITY") if OS.get_environment("QUALITY") != "" else "high")
	Game.race_opts.city = "berat"
	Game.race_opts.env = OS.get_environment("ENV") if OS.get_environment("ENV") != "" else "golden"
	Game.race_opts.laps = 1
	Game.race_opts.reverse = false
	var scene := RaceScene.new()
	add_child(scene)
	scene.set_process(false)
	scene._ui_layer.visible = false
	for c in scene.cars:
		c.visible = false
	var track := scene.track
	var river: CityRiver = scene.river
	var castle := Vector3.ZERO
	for lm: Dictionary in scene.props.landmarks:
		if lm.id == "castle_berat":
			castle = Vector3(float(lm.x), float(lm.y), float(lm.z))
	var gorica: Dictionary = river.data.footbridges[0]
	var ga := Vector3(float(gorica.a[0]), 0, float(gorica.a[1]))
	var gb := Vector3(float(gorica.b[0]), 0, float(gorica.b[1]))
	var bridge_mid := (ga + gb) * 0.5
	bridge_mid.y = float(gorica.surface) + 6.0
	var h := func(p: Vector3, up: float) -> Vector3: return Vector3(p.x, scene.terrain.height_at(p.x, p.z) + up, p.z)
	var views := []
	views.append(["grid", track.pos(2.0, 0.0) + Vector3.UP * 2.3, track.pos(70.0, 0.0) + Vector3.UP * 6.0])
	# Mangalem from the Gorica road, looking north across the river.
	for s in [40.0, 160.0, 300.0]:
		views.append(["mangalem_from_gorica_%d" % int(s), track.pos(s, 3.0) + Vector3.UP * 2.3, castle + Vector3(220, -60, 120)])
	views.append(["panorama", h.call(bridge_mid + Vector3(260, 0, 140), 0.0) + Vector3.UP * 26.0, castle + Vector3(180, -70, 60)])
	views.append(["gorica_bridge", h.call(bridge_mid + Vector3(90, 0, -30), 2.5), bridge_mid])
	views.append(["gorica_bridge_low", bridge_mid + Vector3(-60, -4.0, 12), bridge_mid + Vector3(0, -2, 0)])
	# Close to each quarter from the race road: the house nearest the road.
	var houses: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OldQuarter.path_for("berat")))
	for q in [[0, "mangalem_close"], [1, "gorica_close"]]:
		var best := Vector2.ZERO
		var best_d := INF
		var centre := Vector2.ZERO
		var count := 0
		for house: Dictionary in houses.houses:
			if int(house.q) != int(q[0]):
				continue
			var c := Vector2.ZERO
			for p: Array in house.ring:
				c += Vector2(float(p[0]), float(p[1]))
			c /= house.ring.size()
			centre += c
			count += 1
			var d := track.dist_to(c.x, c.y)
			if d < best_d:
				best_d = d
				best = c
		centre /= maxi(count, 1)
		var s := track.locate_xz(best.x, best.y).x
		var eye := track.pos(s - 35.0, 0.0) + Vector3.UP * 2.4
		views.append([q[1], eye, h.call(Vector3(centre.x, 0, centre.y), 8.0)])
		views.append([str(q[1]) + "_houses", track.pos(s, 0.0) + Vector3.UP * 2.0, h.call(Vector3(best.x, 0, best.y), 5.0)])
	views.append(["castle", h.call(castle + Vector3(260, 0, 260), 30.0), castle + Vector3(0, 10, 60)])
	views.append(["castle_aerial", castle + Vector3(-220, 260, 380), castle])
	views.append(["castle_walls", h.call(castle + Vector3(-160, 0, -40), 3.0), h.call(castle + Vector3(-60, 0, -10), 12.0)])
	var b0: Dictionary = river.data.bridges[0]
	var bm := Vector3((float(b0.a[0]) + float(b0.b[0])) * 0.5, float(b0.deck), (float(b0.a[1]) + float(b0.b[1])) * 0.5)
	var flow_i := int(b0.river)
	var flow := Vector3(river.tan[flow_i].x, 0, river.tan[flow_i].y)
	views.append(["race_bridge", bm + flow * 70.0 + Vector3.UP * 1.0, bm + Vector3.DOWN * 2.0])
	views.append(["river_upstream", bridge_mid + Vector3.UP * 1.5, bridge_mid + Vector3(300, -6, -80)])
	views.append(["top_gorica", bridge_mid + Vector3(0, 260, 1), bridge_mid])
	views.append(["top_mangalem", bridge_mid + Vector3(380, 300, -60), bridge_mid + Vector3(380, 0, -59)])
	var only := OS.get_environment("VIEWS").split(",", false)
	var out := OS.get_environment("SHOTS")
	print("BERAT VISUAL: %d views; %d houses, %d windows, river %d water chunks, %d towers" % [views.size(), scene.quarters.houses, scene.quarters.windows, river.water_chunks, 0])
	for v in views:
		var wanted := only.is_empty()
		for prefix in only:
			wanted = wanted or str(v[0]).begins_with(prefix)
		if not wanted:
			continue
		var cam := Camera3D.new()
		add_child(cam)
		cam.fov = 66.0
		cam.far = 4000.0
		cam.look_at_from_position(v[1], v[2], Vector3.UP)
		cam.current = true
		scene.sky.follow(cam.global_position)
		scene.props.update_vegetation(cam.global_position, -cam.global_basis.z)
		for i in 12:
			await get_tree().process_frame
		if out != "":
			get_viewport().get_texture().get_image().save_png("%s/berat_%s.png" % [out, v[0]])
		cam.queue_free()
	print("BERAT VISUAL: done")
	get_tree().quit()
